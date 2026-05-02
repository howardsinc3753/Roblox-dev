--!strict
-- Handles player data loading, saving, and in-memory cache.
-- Uses DataStoreService for persistence.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataTemplate = require(ReplicatedStorage.Shared.Modules:WaitForChild("PlayerDataTemplate"))

local DATA_STORE_NAME = "DragonWarz_PlayerData_v1"
local SAVE_INTERVAL = 60 -- auto-save every 60 seconds

local DataManager = {}

-- In-memory cache: userId → PlayerData
local cache: { [number]: PlayerDataTemplate.PlayerData } = {}
local dataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)

function DataManager.loadPlayer(player: Player): PlayerDataTemplate.PlayerData
	local userId = player.UserId
	local data: PlayerDataTemplate.PlayerData

	local ok, result = pcall(function()
		return dataStore:GetAsync(`player_{userId}`)
	end)

	if ok and result then
		-- Merge with default to handle schema migrations
		local default = PlayerDataTemplate.getDefault()
		for key, value in default :: any do
			if (result :: any)[key] == nil then
				(result :: any)[key] = value
			end
		end
		data = result :: PlayerDataTemplate.PlayerData
	else
		if not ok then
			warn(`[DataManager] Failed to load data for {player.Name}: {result}`)
		end
		data = PlayerDataTemplate.getDefault()
	end

	cache[userId] = data
	return data
end

function DataManager.savePlayer(player: Player): boolean
	local userId = player.UserId
	local data = cache[userId]
	if not data then
		return false
	end

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

return DataManager
