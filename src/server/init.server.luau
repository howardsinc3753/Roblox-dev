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
local ArenaBuilder = require(script.ArenaBuilder)

print("[Server] Dragon Warz server starting...")

-- Build the arena first
ArenaBuilder.build()

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
local syncTimerRemote = getRemote("SyncTimer")
local specialEffectRemote = getRemote("SpecialEffect")
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
	if data.unlockedDragons[id] then return end
	if data.coins < dragon.cost then return end

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
			RoundManager.recordKill(player, hitPlayer)
			DataManager.addCoins(player, 10)
			updateCoinsRemote:FireClient(player, DataManager.getCoins(player))

			local data = DataManager.getData(player)
			if data then data.stats.totalKills += 1 end
			local victimData = DataManager.getData(hitPlayer)
			if victimData then victimData.stats.totalDeaths += 1 end

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

-- Special ability — all 6 elements implemented
useSpecialRemote.OnServerEvent:Connect(function(player: Player)
	if not CombatManager.canUseSpecial(player) then return end
	if not RoundManager.isActive() then return end

	CombatManager.recordSpecial(player)
	local state = CombatManager.getState(player)
	if not state then return end

	local dragon = DragonConfig[state.dragonId]
	if not dragon then return end

	local character = player.Character
	if not character or not character.PrimaryPart then return end
	local pos = character.PrimaryPart.Position

	if dragon.element == "Fire" then
		-- Fireball Burst: AoE damage around the player
		local nearby = CombatManager.findPlayersInRadius(pos, 40, player)
		for _, target in nearby do
			local killed, _ = CombatManager.applyDamage(target, dragon.damage * 2)
			damagePlayerRemote:FireAllClients(target.UserId, dragon.damage * 2)
			if killed then
				RoundManager.recordKill(player, target)
				DataManager.addCoins(player, 10)
				updateCoinsRemote:FireClient(player, DataManager.getCoins(player))
				playerKORemote:FireAllClients(player.UserId, target.UserId)
				task.delay(RESPAWN_TIME, function()
					if target and target.Parent then
						CombatManager.respawn(target)
						local tData = DataManager.getData(target)
						DragonSpawner.spawn(target, if tData then tData.selectedDragon else "Ember")
					end
				end)
			end
		end
		specialEffectRemote:FireAllClients(player.UserId, "Fire", pos)

	elseif dragon.element == "Ice" then
		-- Ice Wall: temporary shield — heal self 40 HP
		CombatManager.healPlayer(player, 40)
		specialEffectRemote:FireAllClients(player.UserId, "Ice", pos)

	elseif dragon.element == "Lightning" then
		-- Chain Lightning: hit up to 3 nearby enemies
		local nearby = CombatManager.findPlayersInRadius(pos, 60, player)
		local hitCount = 0
		for _, target in nearby do
			if hitCount >= 3 then break end
			hitCount += 1
			local killed, _ = CombatManager.applyDamage(target, dragon.damage)
			damagePlayerRemote:FireAllClients(target.UserId, dragon.damage)
			if killed then
				RoundManager.recordKill(player, target)
				DataManager.addCoins(player, 10)
				updateCoinsRemote:FireClient(player, DataManager.getCoins(player))
				playerKORemote:FireAllClients(player.UserId, target.UserId)
				task.delay(RESPAWN_TIME, function()
					if target and target.Parent then
						CombatManager.respawn(target)
						local tData = DataManager.getData(target)
						DragonSpawner.spawn(target, if tData then tData.selectedDragon else "Ember")
					end
				end)
			end
		end
		specialEffectRemote:FireAllClients(player.UserId, "Lightning", pos)

	elseif dragon.element == "Earth" then
		-- Rock Armor: +50 bonus HP
		CombatManager.addArmor(player, 50)
		specialEffectRemote:FireAllClients(player.UserId, "Earth", pos)

	elseif dragon.element == "Dark" then
		-- Invisibility: make character invisible for 3 seconds
		specialEffectRemote:FireAllClients(player.UserId, "Dark", pos)
		-- Server-side: mark temporarily untargetable
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				(part :: BasePart).Transparency = 1
			end
		end
		task.delay(3, function()
			if character and character.Parent then
				local dragonCfg = DragonConfig[state.dragonId]
				for _, part in character:GetDescendants() do
					if part:IsA("BasePart") then
						(part :: BasePart).Transparency = 0
					end
				end
			end
		end)

	elseif dragon.element == "Light" then
		-- Heal Pulse: heal self and nearby allies 30 HP
		CombatManager.healPlayer(player, 30)
		local nearby = CombatManager.findPlayersInRadius(pos, 50, player)
		for _, target in nearby do
			CombatManager.healPlayer(target, 30)
		end
		specialEffectRemote:FireAllClients(player.UserId, "Light", pos)
	end
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
		local roundState = RoundManager.getState()
		roundStartRemote:FireAllClients(roundState.roundNumber, 120)

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

	-- onRoundEnd: award participation + win bonus, fire RoundEnd with per-player
	-- coins-earned data so the client can show a "you earned X coins" summary.
	function()
		local winner = RoundManager.getWinner()
		local scoreboard = RoundManager.getScoreboard()
		local PARTICIPATION = 5
		local WIN_BONUS = 25

		-- coinsEarnedThisRound: per-userId payout for the summary screen.
		-- Kills are already paid in real time as they happen, so this only
		-- includes the end-of-round bonuses (participation + winner).
		local coinsEarnedThisRound: { [number]: number } = {}

		for _, player in Players:GetPlayers() do
			local earned = PARTICIPATION
			if winner and winner.UserId == player.UserId then
				earned += WIN_BONUS
			end
			DataManager.addCoins(player, earned)
			coinsEarnedThisRound[player.UserId] = earned
			updateCoinsRemote:FireClient(player, DataManager.getCoins(player))
		end

		roundEndRemote:FireAllClients(
			if winner then winner.UserId else 0,
			scoreboard,
			coinsEarnedThisRound
		)
	end
)

-- Periodic timer sync to clients (every 5 seconds)
task.spawn(function()
	while true do
		task.wait(5)
		local roundState = RoundManager.getState()
		if roundState.active then
			syncTimerRemote:FireAllClients(roundState.timeRemaining, roundState.roundNumber)
		end
	end
end)

-- Start the round loop
RoundManager.startLoop()

-- Start auto-save loop
DataManager.startAutoSave()

print("[Server] Dragon Warz server ready!")
