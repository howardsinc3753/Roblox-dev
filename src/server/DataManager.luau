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
--
-- Workspace attribute toggles (set in Studio Properties → Attributes):
--   STUDIO_FRESH_PLAYER (bool) — bypass ALL overrides and QA the genuine
--     "Day 1, 0 coins, 2 dragons, 0 upgrades" new-player UX. Takes
--     precedence over every other Studio toggle. Use this when testing
--     the welcome banner, locked dragons, first-Lair tutorial, etc.
--   STUDIO_MAXED_UPGRADES (bool) — Sprint 7: max all stat upgrades on all
--     dragons so the combat balance can be tested at the upgrade ceiling.
--     Mutually exclusive with FRESH_PLAYER (which wins).
local STUDIO_TEST_COINS = 1000
local function applyStudioOverrides(data: PlayerDataTemplate.PlayerData)
	if not RunService:IsStudio() then return end
	-- FRESH_PLAYER short-circuits everything: leaves data exactly as-saved
	-- (or as-default for new accounts) so the kid sees the real new-player
	-- flow. Don't add code paths after this return without thinking through
	-- the FRESH_PLAYER intent.
	if workspace:GetAttribute("STUDIO_FRESH_PLAYER") == true then return end
	for dragonId in DragonConfig do
		data.unlockedDragons[dragonId] = true
	end
	if data.coins < STUDIO_TEST_COINS then
		data.coins = STUDIO_TEST_COINS
	end
	-- Sprint 7: max upgrades for combat-balance testing. Off by default —
	-- the standard Studio override above just unlocks dragons + grants
	-- coins, so QA still has to spend coins through the upgrade UI to
	-- exercise the purchase flow. Flip this toggle when testing how
	-- maxed-out combat feels (boss-wave damage thresholds, speed cap, etc).
	if workspace:GetAttribute("STUDIO_MAXED_UPGRADES") == true then
		for dragonId in DragonConfig do
			data.dragonUpgrades[dragonId] = { atk = 5, def = 5, spd = 5, special = 5 }
		end
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
			warn(`[DataManager] Failed to load data for userId={player.UserId}: {result}`)
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
		warn(`[DataManager] Failed to save data for userId={player.UserId}: {err}`)
		return false
	end
	return true
end

function DataManager.getData(player: Player): PlayerDataTemplate.PlayerData?
	return cache[player.UserId]
end

function DataManager.unloadPlayer(player: Player)
	-- Strip the transient welcomeBonus before save so it doesn't persist to
	-- DataStore and replay on a same-day re-join. This is the second leg of
	-- the same-day banner-replay fix; the first is in processLogin's diff==0
	-- branch (which clears it on next load if a stale value somehow slipped
	-- through).
	local data = cache[player.UserId]
	if data then
		data.welcomeBonus = nil
	end
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

-- Retention tunables sourced from PlayerDataTemplate so the client's
-- WelcomeBanner reads the same MAX_STREAK_FOR_BONUS value we use here for
-- bonus math. Single source of truth — bumping one side without the other
-- desyncs the "X more days for max streak" copy.
local DAILY_LOGIN_BONUS = PlayerDataTemplate.RETENTION.DAILY_LOGIN_BONUS
local STREAK_BONUS_PER_DAY = PlayerDataTemplate.RETENTION.STREAK_BONUS_PER_DAY
local MAX_STREAK_FOR_BONUS = PlayerDataTemplate.RETENTION.MAX_STREAK_FOR_BONUS
local FIRST_WIN_BONUS = PlayerDataTemplate.RETENTION.FIRST_WIN_BONUS

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
	-- IMPORTANT: hour=12 is a deliberate DST defense, not arbitrary. os.time
	-- interprets table fields as LOCAL time, and DST transitions make a
	-- calendar day 23 or 25 hours long. Anchoring at NOON means the 1-hour
	-- DST shift can never push the timestamp across a day boundary, so the
	-- floor((t2 - t1) / 86400) division still yields the correct day count.
	-- DO NOT change to hour=0 or hour=23 — both are within the DST danger
	-- zone and will silently break streak math twice a year for users in
	-- DST-observing regions.
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
		-- Already logged in today — no bonus AND clear any stale welcomeBonus.
		-- Why clear: welcomeBonus lives inside PlayerData and gets persisted
		-- to DataStore on save. Without this clear, a player who logs out and
		-- back in on the same day would replay yesterday's banner with no
		-- actual coin grant (the bonus was already applied earlier today).
		data.welcomeBonus = nil
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
	-- CAVEAT: this is a SNAPSHOT taken at login time. If a player wins later
	-- in the session and we ever add a "show welcome banner again" feature,
	-- this field would be stale (still true even after the win). Today the
	-- banner self-throttles via shownThisSession, so the staleness is
	-- invisible — but a future re-show feature must recompute this.
	local firstWinAvailable = data.lastWinDay ~= today

	data.welcomeBonus = {
		streak = data.loginStreak,
		dailyCoins = DAILY_LOGIN_BONUS,
		streakCoins = streakCoins,
		totalCoins = totalCoins,
		firstWinAvailable = firstWinAvailable,
	}

	-- Log UserId not Name. Targeting kids (9-16); the published place will
	-- have COPPA scope and we should keep PII out of server logs by default.
	print(`[DataManager] login userId={player.UserId}: streak={data.loginStreak}, +{totalCoins} coins`)
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
	-- UserId not Name; see processLogin comment on COPPA scope.
	print(`[DataManager] userId={player.UserId} claimed first-win-of-day bonus +{FIRST_WIN_BONUS}`)
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
