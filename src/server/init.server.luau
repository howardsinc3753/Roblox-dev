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
local NPCManager = require(script.NPCManager)

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
local damageNPCRemote = getRemote("DamageNPC")
local npcBreathFiredRemote = getRemote("NPCBreathFired")
local lockOnTargetRemote = getRemote("LockOnTarget")
local lockedByEnemyRemote = getRemote("LockedByEnemy")
local getPlayerDataFunc = getRemoteFunction("GetPlayerData")

-- ================================
-- PLAYER JOIN / LEAVE
-- ================================

local RESPAWN_TIME = 5

Players.PlayerAdded:Connect(function(player: Player)
	print(`[Server] {player.Name} joined`)

	-- Load persistent data
	local data = DataManager.loadPlayer(player)
	-- Process daily login: streak update + bonus coins + populate welcomeBonus.
	-- Must run BEFORE the initial UpdateCoins fire so the client sees the new
	-- balance (with the bonus applied). The welcomeBonus payload reaches the
	-- client via the existing GetPlayerData refresh — no new remote needed.
	DataManager.processLogin(player)
	RoundManager.initPlayerScore(player)

	-- Spawn their dragon
	local dragonId = data.selectedDragon
	CombatManager.initPlayer(player, dragonId)
	DragonSpawner.spawn(player, dragonId)

	-- Send initial data to client (coins now include the daily bonus)
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

-- Lock-on relay: client reports its current lock target. Server forwards
-- a brief warning to the targeted player so they know to dodge. We don't
-- track persistent state — each client message is "this is who I'm locked
-- on right now" and we ping the target once. Thrash-spammy clients are
-- self-limited because LockOnController only sends on state changes.
lockOnTargetRemote.OnServerEvent:Connect(function(player: Player, targetUserId: unknown)
	if typeof(targetUserId) ~= "number" then return end
	if targetUserId == 0 then return end -- 0 = unlocked, no warning needed
	if targetUserId == player.UserId then return end -- can't lock self
	local target = Players:GetPlayerByUserId(targetUserId :: number)
	if not target then return end
	-- Tell target who locked them. Client uses player name to display.
	lockedByEnemyRemote:FireClient(target, player.UserId, player.Name)
end)

-- Breath attack: checks players first, then NPCs (priority: PvP fights take
-- precedence when both are in the cone, so cooperating against NPCs doesn't
-- accidentally heal the human meta).
fireBreathRemote.OnServerEvent:Connect(function(player: Player, origin: unknown, direction: unknown)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	if not CombatManager.canFireBreath(player) then return end
	if not RoundManager.isActive() then return end

	CombatManager.recordBreath(player)

	local state = CombatManager.getState(player)
	if not state then return end

	local dragon = DragonConfig[state.dragonId]
	if not dragon then return end

	-- Fake projectile travel time. The client-side breath visual takes
	-- distance/150 seconds to traverse to the target. Server applies damage
	-- at hit-detection time (instant cone test, anti-cheat) but DELAYS the
	-- damage application so visual + HP drop arrive together. Cap at 0.4s
	-- so very long shots don't feel laggy.
	local PROJECTILE_SPEED = 150 -- studs/sec, must match CombatInput's tween speed
	local TRAVEL_CAP = 0.4 -- seconds; max delay even for very long shots

	-- Try player target first
	local hitPlayer = CombatManager.findHitPlayer(player, origin :: Vector3, direction :: Vector3)
	if hitPlayer then
		CombatManager.recordDamageDealt(player) -- pause attacker's HP regen (resolved at fire-time, fair)
		-- Damage falloff: scale base damage by distance from breath origin.
		-- Close-range = full damage, long-range (>=80 studs) = 50%.
		local hitTargetPos = (hitPlayer.Character and hitPlayer.Character.PrimaryPart)
			and hitPlayer.Character.PrimaryPart.Position
			or origin :: Vector3
		local hitDist = (hitTargetPos - origin :: Vector3).Magnitude
		local falloffDmg = math.floor(dragon.damage * CombatManager.distanceFalloff(hitDist))
		local travelTime = math.min(hitDist / PROJECTILE_SPEED, TRAVEL_CAP)

		-- Capture shooter position now (before delay) so the damage-direction
		-- arc points at where the shooter was when they fired, not later.
		local shooterPos = origin :: Vector3
		if player.Character and player.Character.PrimaryPart then
			shooterPos = player.Character.PrimaryPart.Position
		end

		-- Delay damage application + remote fires by travel time. Hit was
		-- locked-in above (predictive hit model — same as League/Overwatch
		-- non-projectile abilities). If the victim disconnects or dies during
		-- the brief travel, applyDamage's alive check no-ops gracefully.
		task.delay(travelTime, function()
			if not hitPlayer.Parent then return end -- left the server
			local killed, damage = CombatManager.applyDamage(hitPlayer, falloffDmg)
			damagePlayerRemote:FireAllClients(hitPlayer.UserId, damage, shooterPos)

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

				task.delay(RESPAWN_TIME, function()
					if hitPlayer and hitPlayer.Parent then
						local vData = DataManager.getData(hitPlayer)
						local vDragonId = if vData then vData.selectedDragon else "Ember"
						CombatManager.respawn(hitPlayer)
						DragonSpawner.spawn(hitPlayer, vDragonId)
					end
				end)
			end
		end)
		return
	end

	-- No player hit — check NPCs in the cone
	local hitNpc = CombatManager.findHitNPC(NPCManager.getAlive(), origin :: Vector3, direction :: Vector3)
	if hitNpc then
		CombatManager.recordDamageDealt(player) -- pause attacker's HP regen (NPC kills count too)
		-- Same falloff curve for NPCs — consistent skill expression.
		local npcDist = (hitNpc.rootPart.Position - origin :: Vector3).Magnitude
		local npcFalloffDmg = math.floor(dragon.damage * CombatManager.distanceFalloff(npcDist))
		local npcTravelTime = math.min(npcDist / PROJECTILE_SPEED, TRAVEL_CAP)

		-- Same predictive-hit pattern as players. NPCManager.applyDamage
		-- handles the "already dead during travel" case via its alive check.
		task.delay(npcTravelTime, function()
			if not hitNpc.model or not hitNpc.model.Parent then return end
			NPCManager.applyDamage(hitNpc.id, npcFalloffDmg, player.UserId)
			-- H1+H3 fix: send NPC model + damage to the SHOOTER ONLY. Client renders
			-- the floating "-X" above the NPC and plays the hit sound. Other clients
			-- don't get spammed with hit sounds for someone else's combat.
			damageNPCRemote:FireClient(player, hitNpc.model, npcFalloffDmg)
		end)
	end
end)

-- Special ability — all 6 elements implemented.
-- Client now passes camera direction (2nd arg) so cone specials aim where
-- the player is looking, not where the body is tilted (climb/dive/bank).
useSpecialRemote.OnServerEvent:Connect(function(player: Player, clientDirection: unknown)
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

	-- Resolve cone direction. Trust the client's camera direction if it's a
	-- valid Vector3 with reasonable magnitude (Roblox-validated server-side
	-- to prevent garbage payloads). Fall back to body LookVector if missing
	-- or invalid — better to aim slightly off than to no-op the special.
	local forward: Vector3
	if typeof(clientDirection) == "Vector3" and clientDirection.Magnitude > 0.5 and clientDirection.Magnitude < 2 then
		forward = clientDirection.Unit
	else
		forward = character.PrimaryPart.CFrame.LookVector
	end

	if dragon.element == "Fire" then
		-- Fire Vortex: 90-degree forward cone of flame, 60 stud range. Hits
		-- everything (players + NPCs) in the swath. Replaces the old AoE-around-
		-- self behavior — feels like a real panic-button now instead of a
		-- self-centered burst.
		local FIRE_CONE_RANGE = 60
		local FIRE_CONE_DOT = 0.7 -- ~45-degree half-angle = 90 deg cone
		local fireDmg = dragon.damage * 2

		local conePlayers = CombatManager.findPlayersInCone(pos, forward, FIRE_CONE_RANGE, FIRE_CONE_DOT, player)
		for _, target in conePlayers do
			CombatManager.recordDamageDealt(player)
			local killed, _ = CombatManager.applyDamage(target, fireDmg)
			damagePlayerRemote:FireAllClients(target.UserId, fireDmg, pos)
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

		-- Same cone hits NPCs. The user is playing solo with PvE NPCs as the
		-- main threat — specials would feel pointless if they didn't sweep them.
		local coneNPCs = CombatManager.findNPCsInCone(NPCManager.getAlive(), pos, forward, FIRE_CONE_RANGE, FIRE_CONE_DOT)
		for _, npc in coneNPCs do
			CombatManager.recordDamageDealt(player)
			NPCManager.applyDamage(npc.id, fireDmg, player.UserId)
			damageNPCRemote:FireClient(player, npc.model, fireDmg)
		end

		-- 4th arg = direction. Client renders the vortex VFX as a forward cone.
		specialEffectRemote:FireAllClients(player.UserId, "Fire", pos, forward)

	elseif dragon.element == "Ice" then
		-- Ice Wall: temporary shield — heal self 40 HP
		CombatManager.healPlayer(player, 40)
		specialEffectRemote:FireAllClients(player.UserId, "Ice", pos, forward)

	elseif dragon.element == "Lightning" then
		-- Chain Lightning: forward cone hitting up to 3 (players or NPCs)
		local LIGHTNING_CONE_RANGE = 70
		local LIGHTNING_CONE_DOT = 0.7

		local hitCount = 0
		local conePlayers = CombatManager.findPlayersInCone(pos, forward, LIGHTNING_CONE_RANGE, LIGHTNING_CONE_DOT, player)
		for _, target in conePlayers do
			if hitCount >= 3 then break end
			hitCount += 1
			CombatManager.recordDamageDealt(player)
			local killed, _ = CombatManager.applyDamage(target, dragon.damage)
			damagePlayerRemote:FireAllClients(target.UserId, dragon.damage, pos)
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

		-- Lightning chain extends to NPCs too. Whatever player slots aren't
		-- filled by the 3-target cap, NPCs can take the rest.
		if hitCount < 3 then
			local coneNPCs = CombatManager.findNPCsInCone(NPCManager.getAlive(), pos, forward, LIGHTNING_CONE_RANGE, LIGHTNING_CONE_DOT)
			for _, npc in coneNPCs do
				if hitCount >= 3 then break end
				hitCount += 1
				CombatManager.recordDamageDealt(player)
				NPCManager.applyDamage(npc.id, dragon.damage, player.UserId)
				damageNPCRemote:FireClient(player, npc.model, dragon.damage)
			end
		end

		specialEffectRemote:FireAllClients(player.UserId, "Lightning", pos, forward)

	elseif dragon.element == "Earth" then
		-- Rock Armor: +50 bonus HP
		CombatManager.addArmor(player, 50)
		specialEffectRemote:FireAllClients(player.UserId, "Earth", pos, forward)

	elseif dragon.element == "Dark" then
		-- Invisibility: make character invisible for 3 seconds
		specialEffectRemote:FireAllClients(player.UserId, "Dark", pos, forward)
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
		specialEffectRemote:FireAllClients(player.UserId, "Light", pos, forward)
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

	-- onRoundEnd: award participation + win bonus + first-win-of-day bonus.
	-- Fire RoundEnd with per-player coins-earned data so the client can show
	-- a "you earned X coins" summary. firstWinClaimed[userId] tells the client
	-- whether to render the gold "FIRST WIN TODAY +50" highlight.
	function()
		local winner = RoundManager.getWinner()
		local scoreboard = RoundManager.getScoreboard()
		local PARTICIPATION = 5
		local WIN_BONUS = 25

		local coinsEarnedThisRound: { [number]: number } = {}
		local firstWinClaimed: { [number]: boolean } = {}

		for _, player in Players:GetPlayers() do
			local earned = PARTICIPATION
			if winner and winner.UserId == player.UserId then
				earned += WIN_BONUS
				-- Stack the first-win-of-day bonus on top of the regular win bonus.
				-- claimFirstWin is idempotent per UTC day (returns false if already
				-- claimed today), so this only fires once per day per player.
				local claimed, bonus = DataManager.claimFirstWin(player)
				if claimed then
					earned += bonus
					firstWinClaimed[player.UserId] = true
				end
			end
			DataManager.addCoins(player, earned)
			coinsEarnedThisRound[player.UserId] = earned
			updateCoinsRemote:FireClient(player, DataManager.getCoins(player))
		end

		roundEndRemote:FireAllClients(
			if winner then winner.UserId else 0,
			scoreboard,
			coinsEarnedThisRound,
			firstWinClaimed
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

-- Start HP regen loop (heals players who haven't taken/dealt damage for 3s)
CombatManager.startRegenLoop()

-- ================================
-- NPC SURVIVAL SYSTEM
-- ================================

-- Hook NPC kills into the existing reward + kill feed pipeline.
-- When an NPC dies, the killer gets coins, the kill feed shows it,
-- and the KO sound plays for everyone (via PlayerKO with NPC userId=0).
NPCManager.setKillCallback(function(killerUserId: number, enemyType: string, coinReward: number)
	local killer = Players:GetPlayerByUserId(killerUserId)
	if not killer then return end

	DataManager.addCoins(killer, coinReward)
	updateCoinsRemote:FireClient(killer, DataManager.getCoins(killer))

	local data = DataManager.getData(killer)
	if data then data.stats.totalKills += 1 end

	-- Fire KO event so the kill feed shows "[killer] eliminated [Enemy Type]"
	-- userId 0 indicates NPC; client renders the enemy name from enemyType arg.
	playerKORemote:FireAllClients(killerUserId, 0, enemyType)
end)

-- AI damage callback: when an NPC's AI tick decides to fire breath at a player,
-- the damage flows through CombatManager so all the existing Humanoid sync,
-- KO handling, respawn timing, and stats updates apply consistently.
-- Extra args (npcModel, color) wire the H2 fix: clients render a visible
-- projectile from the NPC to the target instead of invisible-damage attacks.
local function npcDamagePlayer(target: Player, damage: number, source: Vector3, npcModel: Model?, color: Color3?)
	if not RoundManager.isActive() then return end

	-- H2: broadcast breath visual to ALL clients so everyone sees the attack
	-- (not just the victim). Color comes from the NPC's element so visuals match.
	if npcModel and color and target.Character and target.Character.PrimaryPart then
		npcBreathFiredRemote:FireAllClients(npcModel, target.Character.PrimaryPart.Position, color)
	end

	local killed, actualDamage = CombatManager.applyDamage(target, damage)
	-- 3rd arg = source position, for the damage-direction indicator on the victim's client.
	-- `source` is the NPC's position (passed in by NPCManager AI tick).
	damagePlayerRemote:FireAllClients(target.UserId, actualDamage, source)

	if killed then
		local victimData = DataManager.getData(target)
		if victimData then victimData.stats.totalDeaths += 1 end

		-- userId 0 in the killer slot means "killed by NPC" — kill feed shows enemy
		playerKORemote:FireAllClients(0, target.UserId, "Enemy")

		task.delay(RESPAWN_TIME, function()
			if target and target.Parent then
				local vData = DataManager.getData(target)
				local vDragonId = if vData then vData.selectedDragon else "Ember"
				CombatManager.respawn(target)
				DragonSpawner.spawn(target, vDragonId)
			end
		end)
	end
end

-- NPC AI lock-on warning. Fires LockedByEnemy to a player when an NPC
-- acquires them as a target. Per-player rate-limit prevents 5 NPCs all
-- locking onto you in the same tick from stacking 5 sirens. 2.5s gap
-- between consecutive warnings for the same player feels like the right
-- "calm down, you're already alert" cadence.
local NPC_LOCK_WARNING_COOLDOWN = 2.5
local lastNpcLockWarnAt: { [number]: number } = {} -- userId -> tick()

NPCManager.setLockOnCallback(function(playerUserId: number, enemyName: string)
	local now = tick()
	local last = lastNpcLockWarnAt[playerUserId] or 0
	if now - last < NPC_LOCK_WARNING_COOLDOWN then return end
	lastNpcLockWarnAt[playerUserId] = now

	local target = Players:GetPlayerByUserId(playerUserId)
	if not target then return end
	-- userId 0 in attacker slot = NPC sentinel, matches the playerKO
	-- pattern. Client uses enemyName to display in the warning.
	lockedByEnemyRemote:FireClient(target, 0, enemyName)
end)

-- H4 fix: pass isRoundActive into both AI and wave loops so they don't run
-- during intermission (no wasted ticks, no spectral breath visuals during the
-- 15s dragon-select window).
NPCManager.startAILoop(npcDamagePlayer, RoundManager.isActive)
NPCManager.startWaveLoop(RoundManager.isActive)

print("[Server] Dragon Warz server ready! (with NPC survival system)")
