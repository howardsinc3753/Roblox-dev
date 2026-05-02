--!strict
-- Dragon Warz — Server Entry Point
-- Wires up all server systems: networking, data, combat, rounds, spawning.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Set up remotes first (other modules depend on them)
local NetworkSetup = require(script.NetworkSetup)
local remotesFolder = NetworkSetup.setup()

-- Load server modules
local DataManager = require(script.DataManager)
local CombatManager = require(script.CombatManager)
local RoundManager = require(script.RoundManager)
local DragonSpawner = require(script.DragonSpawner)
local DragonConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("DragonConfig"))

print("[Server] Dragon Warz server starting...")

-- Helper to get a remote
local function getRemote(name: string): RemoteEvent
	return remotesFolder:WaitForChild(name) :: RemoteEvent
end

local function getRemoteFunction(name: string): RemoteFunction
	return remotesFolder:WaitForChild(name) :: RemoteFunction
end

-- Remotes
local selectDragonRemote = getRemote("SelectDragon")
local unlockDragonRemote = getRemote("UnlockDragon")
local fireBreathRemote = getRemote("FireBreath")
local useSpecialRemote = getRemote("UseSpecial")
local damagePlayerRemote = getRemote("DamagePlayer")
local playerKORemote = getRemote("PlayerKO")
local roundStartRemote = getRemote("RoundStart")
local roundEndRemote = getRemote("RoundEnd")
local updateCoinsRemote = getRemote("UpdateCoins")
local spawnDragonRemote = getRemote("SpawnDragon")
local updateScoreboardRemote = getRemote("UpdateScoreboard")
local getPlayerDataFunc = getRemoteFunction("GetPlayerData")

-- ================================
-- PLAYER JOIN / LEAVE
-- ================================

local RESPAWN_TIME = 5

Players.PlayerAdded:Connect(function(player: Player)
	print(`[Server] {player.Name} joined`)

	-- Load persistent data
	local data = DataManager.loadPlayer(player)
	RoundManager.initPlayerScore(player)

	-- Spawn their dragon
	local dragonId = data.selectedDragon
	CombatManager.initPlayer(player, dragonId)
	DragonSpawner.spawn(player, dragonId)

	-- Send initial data to client
	updateCoinsRemote:FireClient(player, data.coins)
	spawnDragonRemote:FireClient(player, dragonId)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	print(`[Server] {player.Name} leaving`)
	DataManager.unloadPlayer(player)
	CombatManager.removePlayer(player)
	RoundManager.removePlayerScore(player)
end)

-- ================================
-- REMOTE EVENT HANDLERS
-- ================================

-- Dragon selection
selectDragonRemote.OnServerEvent:Connect(function(player: Player, dragonId: unknown)
	if typeof(dragonId) ~= "string" then return end
	local id = dragonId :: string

	local data = DataManager.getData(player)
	if not data then return end

	-- Validate dragon exists and is unlocked
	if not DragonConfig[id] then return end
	if not data.unlockedDragons[id] then return end

	data.selectedDragon = id
	CombatManager.initPlayer(player, id)
	DragonSpawner.spawn(player, id)
	spawnDragonRemote:FireClient(player, id)
end)

-- Dragon unlock
unlockDragonRemote.OnServerEvent:Connect(function(player: Player, dragonId: unknown)
	if typeof(dragonId) ~= "string" then return end
	local id = dragonId :: string

	local dragon = DragonConfig[id]
	if not dragon then return end

	local data = DataManager.getData(player)
	if not data then return end
	if data.unlockedDragons[id] then return end -- already owned

	if data.coins < dragon.cost then return end -- can't afford

	data.coins -= dragon.cost
	data.unlockedDragons[id] = true
	updateCoinsRemote:FireClient(player, data.coins)
	print(`[Server] {player.Name} unlocked {id}!`)
end)

-- Breath attack
fireBreathRemote.OnServerEvent:Connect(function(player: Player, origin: unknown, direction: unknown)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end

	if not CombatManager.canFireBreath(player) then return end
	if not RoundManager.isActive() then return end

	CombatManager.recordBreath(player)

	local state = CombatManager.getState(player)
	if not state then return end

	local dragon = DragonConfig[state.dragonId]
	if not dragon then return end

	-- Find hit target
	local hitPlayer = CombatManager.findHitPlayer(player, origin :: Vector3, direction :: Vector3)
	if hitPlayer then
		local killed, damage = CombatManager.applyDamage(hitPlayer, dragon.damage)
		damagePlayerRemote:FireAllClients(hitPlayer.UserId, damage)

		if killed then
			-- Record kill
			RoundManager.recordKill(player, hitPlayer)
			DataManager.addCoins(player, 10)
			updateCoinsRemote:FireClient(player, DataManager.getCoins(player))

			local data = DataManager.getData(player)
			if data then
				data.stats.totalKills += 1
			end
			local victimData = DataManager.getData(hitPlayer)
			if victimData then
				victimData.stats.totalDeaths += 1
			end

			playerKORemote:FireAllClients(player.UserId, hitPlayer.UserId)
			updateScoreboardRemote:FireAllClients(RoundManager.getScoreboard())

			-- Respawn victim after delay
			task.delay(RESPAWN_TIME, function()
				if hitPlayer and hitPlayer.Parent then
					local vData = DataManager.getData(hitPlayer)
					local vDragonId = if vData then vData.selectedDragon else "Ember"
					CombatManager.respawn(hitPlayer)
					DragonSpawner.spawn(hitPlayer, vDragonId)
				end
			end)
		end
	end
end)

-- Special ability
useSpecialRemote.OnServerEvent:Connect(function(player: Player)
	if not CombatManager.canUseSpecial(player) then return end
	if not RoundManager.isActive() then return end

	CombatManager.recordSpecial(player)
	local state = CombatManager.getState(player)
	if not state then return end

	local dragon = DragonConfig[state.dragonId]
	if not dragon then return end

	-- Apply special based on element
	if dragon.element == "Earth" then
		-- Rock Armor: +50 HP
		state.health = math.min(state.health + 50, state.maxHealth + 50)
	elseif dragon.element == "Light" then
		-- Heal Pulse: heal nearby players
		local character = player.Character
		if character and character.PrimaryPart then
			local pos = character.PrimaryPart.Position
			for _, otherPlayer in Players:GetPlayers() do
				if otherPlayer ~= player then
					local otherChar = otherPlayer.Character
					if otherChar and otherChar.PrimaryPart then
						local dist = (otherChar.PrimaryPart.Position - pos).Magnitude
						if dist < 50 then
							local otherState = CombatManager.getState(otherPlayer)
							if otherState and otherState.alive then
								otherState.health = math.min(otherState.health + 30, otherState.maxHealth)
							end
						end
					end
				end
			end
		end
	end
	-- Shadow invisibility, Storm chain lightning, Fire AoE, Ice wall
	-- are handled client-side visually + server validates damage
end)

-- Get player data (RemoteFunction)
getPlayerDataFunc.OnServerInvoke = function(player: Player)
	return DataManager.getData(player)
end

-- ================================
-- ROUND SYSTEM
-- ================================

RoundManager.setCallbacks(
	-- onRoundStart
	function()
		local state = RoundManager.getState()
		roundStartRemote:FireAllClients(state.roundNumber, 120)

		-- Respawn all players
		for _, player in Players:GetPlayers() do
			local data = DataManager.getData(player)
			local dragonId = if data then data.selectedDragon else "Ember"
			CombatManager.initPlayer(player, dragonId)
			DragonSpawner.spawn(player, dragonId)

			if data then
				data.stats.gamesPlayed += 1
			end
		end

		updateScoreboardRemote:FireAllClients(RoundManager.getScoreboard())
	end,

	-- onRoundEnd
	function()
		local winner = RoundManager.getWinner()
		local scoreboard = RoundManager.getScoreboard()

		-- Award participation coins
		for _, player in Players:GetPlayers() do
			DataManager.addCoins(player, 5)
			updateCoinsRemote:FireClient(player, DataManager.getCoins(player))
		end

		roundEndRemote:FireAllClients(
			if winner then winner.UserId else 0,
			scoreboard
		)
	end
)

-- Start the round loop
RoundManager.startLoop()

print("[Server] Dragon Warz server ready!")
