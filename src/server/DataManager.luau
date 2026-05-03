--!strict
-- Handles player data loading, saving, and in-memory cache.
-- Uses DataStoreService for persistence. Includes auto-save loop.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlayerDataTemplate = require(ReplicatedStorage.Shared.Modules:WaitForChild("PlayerDataTemplate"))
local DragonConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("DragonConfig"))

local DATA_STORE_NAME = "DragonWarz_PlayerData_v1"
local SAVE_INTERVAL = 60

-- Studio convenience: unlock the full roster + a coin balance so devs can
-- test all 6 dragons without grinding kills. RunService:IsStudio() is true
-- only in the local Studio editor — production builds (published place)
-- get the normal locked progression. Saving still works in Studio (uses
-- a separate temporary DataStore session), so this only changes initial
-- defaults, not subsequent loads.
local STUDIO_TEST_COINS = 1000
local function applyStudioOverrides(data: PlayerDataTemplate.PlayerData)
	if not RunService:IsStudio() then return end
	for dragonId in DragonConfig do
		data.unlockedDragons[dragonId] = true
	end
	if data.coins < STUDIO_TEST_COINS then
		data.coins = STUDIO_TEST_COINS
	end
end

local DataManager = {}

local cache: { [number]: PlayerDataTemplate.PlayerData } = {}
local dataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)

-- Deep merge: recursively fill in missing keys from default
local function deepMerge(target: any, default: any)
	for key, defaultValue in default do
		if target[key] == nil then
			target[key] = defaultValue
		elseif typeof(defaultValue) == "table" and typeof(target[key]) == "table" then
			deepMerge(target[key], defaultValue)
		end
	end
end

function DataManager.loadPlayer(player: Player): PlayerDataTemplate.PlayerData
	local userId = player.UserId
	local data: PlayerDataTemplate.PlayerData

	local ok, result = pcall(function()
		return dataStore:GetAsync(`player_{userId}`)
	end)

	if ok and result then
		local default = PlayerDataTemplate.getDefault()
		deepMerge(result, default)
		data = result :: PlayerDataTemplate.PlayerData
	else
		if not ok then
			warn(`[DataManager] Failed to load data for {player.Name}: {result}`)
		end
		data = PlayerDataTemplate.getDefault()
	end

	applyStudioOverrides(data)
	cache[userId] = data
	return data
end

function DataManager.savePlayer(player: Player): boolean
	local userId = player.UserId
	local data = cache[userId]
	if not data then return false end

	local ok, err = pcall(function()
		dataStore:SetAsync(`player_{userId}`, data)
	end)

	if not ok then
		warn(`[DataManager] Failed to save data for {player.Name}: {err}`)
		return false
	end
	return true
end

function DataManager.getData(player: Player): PlayerDataTemplate.PlayerData?
	return cache[player.UserId]
end

function DataManager.unloadPlayer(player: Player)
	DataManager.savePlayer(player)
	cache[player.UserId] = nil
end

function DataManager.addCoins(player: Player, amount: number)
	local data = cache[player.UserId]
	if data then
		data.coins += amount
	end
end

function DataManager.getCoins(player: Player): number
	local data = cache[player.UserId]
	return if data then data.coins else 0
end

-- ================================
-- RETENTION (daily login + streak + first-win-of-day)
-- ================================

-- Tunables. If you tweak these, also update the comments in PlayerDataTemplate
-- so the design intent stays documented.
local DAILY_LOGIN_BONUS = 10 -- flat coins for first login each day
local STREAK_BONUS_PER_DAY = 5 -- per consecutive day, capped at MAX_STREAK_FOR_BONUS
local MAX_STREAK_FOR_BONUS = 5 -- streak day at which streak bonus caps
local FIRST_WIN_BONUS = 50 -- "first win of the day" payout, claimed once per UTC day

-- UTC day key as an integer (YYYYMMDD). Integer comparison is faster than
-- string compare, and YYYYMMDD sorts correctly as a number too.
-- Using `os.date("!*t", ...)` with the `!` prefix forces UTC.
local function getDayUTC(timestamp: number?): number
	local t = os.date("!*t", timestamp or os.time())
	return (t.year :: number) * 10000 + (t.month :: number) * 100 + (t.day :: number)
end

-- Day distance (today - yesterday = 1, today - day-before-yesterday = 2, etc).
-- Note: this naively diffs the YYYYMMDD integers which works ONLY when the
-- two dates are in the same month. For cross-month/cross-year we need real
-- date math. We use os.time({year, month, day}) to compute Unix seconds and
-- diff in 86400-second chunks.
local function daysBetween(earlierDay: number, laterDay: number): number
	if earlierDay == 0 then return math.huge end -- never logged in → break streak
	local function unpackDay(d: number)
		local year = math.floor(d / 10000)
		local month = math.floor((d % 10000) / 100)
		local day = d % 100
		return year, month, day
	end
	local y1, m1, d1 = unpackDay(earlierDay)
	local y2, m2, d2 = unpackDay(laterDay)
	-- os.time interprets table fields as LOCAL time on most platforms; for
	-- our integer-day comparison we just need a consistent reference point,
	-- so local time is fine as long as we use it on both sides.
	local t1 = os.time({ year = y1, month = m1, day = d1, hour = 12, min = 0, sec = 0 } :: any)
	local t2 = os.time({ year = y2, month = m2, day = d2, hour = 12, min = 0, sec = 0 } :: any)
	return math.floor((t2 - t1) / 86400)
end

-- Process a player's login: update streak, grant daily bonus, populate the
-- transient welcomeBonus field. Idempotent within a UTC day — calling twice
-- in the same day skips the bonus the second time.
function DataManager.processLogin(player: Player)
	local data = cache[player.UserId]
	if not data then return end

	data.totalLogins += 1
	local today = getDayUTC()
	local diff = daysBetween(data.lastLoginDay, today)

	if diff == 0 then
		-- Already logged in today — no bonus, but keep welcomeBonus from earlier
		-- if it was set this session (shouldn't normally happen, defensive)
		return
	elseif diff == 1 then
		-- Logged in yesterday → streak continues
		data.loginStreak += 1
	else
		-- Missed a day (or first ever login) → streak resets to 1.
		-- MVP: zero grace. If retention data shows streak-breaks correlate with
		-- churn, add a 1-day grace period here later.
		data.loginStreak = 1
	end

	data.lastLoginDay = today

	local streakCoins = math.min(data.loginStreak, MAX_STREAK_FOR_BONUS) * STREAK_BONUS_PER_DAY
	local totalCoins = DAILY_LOGIN_BONUS + streakCoins
	data.coins += totalCoins

	-- firstWinAvailable: true if they haven't claimed today's first-win bonus yet.
	-- Used by the welcome banner to tease the next reward in the same flow.
	local firstWinAvailable = data.lastWinDay ~= today

	data.welcomeBonus = {
		streak = data.loginStreak,
		dailyCoins = DAILY_LOGIN_BONUS,
		streakCoins = streakCoins,
		totalCoins = totalCoins,
		firstWinAvailable = firstWinAvailable,
	}

	print(`[DataManager] {player.Name} login: streak={data.loginStreak}, +{totalCoins} coins`)
end

-- Claim the first-win-of-day bonus. Returns (claimed: boolean, bonus: number).
-- Server calls this when a round ends and there's a winner.
function DataManager.claimFirstWin(player: Player): (boolean, number)
	local data = cache[player.UserId]
	if not data then return false, 0 end
	local today = getDayUTC()
	if data.lastWinDay == today then
		return false, 0 -- already claimed today
	end
	data.lastWinDay = today
	data.coins += FIRST_WIN_BONUS
	print(`[DataManager] {player.Name} claimed first-win-of-day bonus +{FIRST_WIN_BONUS}`)
	return true, FIRST_WIN_BONUS
end

-- Auto-save all online players periodically
function DataManager.startAutoSave()
	task.spawn(function()
		while true do
			task.wait(SAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				DataManager.savePlayer(player)
			end
			print(`[DataManager] Auto-saved {#Players:GetPlayers()} players`)
		end
	end)
end

return DataManager
