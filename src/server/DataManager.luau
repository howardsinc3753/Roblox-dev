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
