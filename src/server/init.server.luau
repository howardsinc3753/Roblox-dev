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
local RateLimiter = require(script.RateLimiter)
local LairBuilder = require(script.LairBuilder)
local ZoneManager = require(script.ZoneManager)
local DragonProgression = require(script.DragonProgression)
local Analytics = require(script.Analytics)
local BossManager = require(script.BossManager)
local CollectionService = game:GetService("CollectionService")

-- Disable Roblox's default character auto-spawn. Without this, Roblox
-- spawns a default humanoid before our PlayerAdded handler runs — user
-- sees the default character first, then our DragonSpawner's dragon
-- replaces it. The intermediate default-spawn position (often a Roblox
-- SpawnLocation at origin) showed before round start, then the round
-- start respawn put them in the Lair. This makes our spawn pipeline
-- the single source of truth.
Players.CharacterAutoLoads = false

print("[Server] Dragon Warz server starting...")

-- Sprint 5 Part F: all spawns default to the Lair (safe zone). The Arena
-- is reached via portal teleport (Part E), not direct spawn. Replaces all
-- previous spawnInLair(p, d) calls. The arenaSpawn helper below is
-- used by the Lair portal Touched handler to send players into combat.
local function spawnInLair(player: Player, dragonId: string)
	-- DragonSpawner.spawn (NOT spawnInLair) — the previous version recursed
	-- because the replace-all sed caught this internal call too. Every spawn
	-- attempt hit infinite recursion and the player got Roblox's default
	-- spawn fallback instead of our Lair drop.
	return DragonSpawner.spawn(player, dragonId, LairBuilder.getRandomSpawnPoint())
end

local function teleportToArena(player: Player)
	local character = player.Character
	if not character or not character.PrimaryPart then return end
	local arenaPos = DragonSpawner.getRandomSpawnPoint()
	character:PivotTo(CFrame.new(arenaPos))
end

local function teleportToLair(player: Player)
	local character = player.Character
	if not character or not character.PrimaryPart then return end
	local lairPos = LairBuilder.getRandomSpawnPoint()
	character:PivotTo(CFrame.new(lairPos))
end

-- Build the arena (combat zone) and lair (safe hub) at server start.
-- Both static, so no per-player cost. Sprint 5 Parts C+D now live: ZoneManager
-- tracks who's in the Lair vs Arena and CombatManager/NPCManager honor the
-- safe-zone rule. Part E adds the portal teleport between them.
ArenaBuilder.build()
LairBuilder.build()

-- Sprint 5 Part C: start the per-player Zone attribute updater. After this,
-- Player:GetAttribute("Zone") is "Lair" or "Arena" and stays current at 5Hz.
-- Combat code calls ZoneManager.isPlayerInLair() directly for real-time tests.
ZoneManager.startTracking()

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
local useShieldRemote = getRemote("UseShield")
local shieldActivatedRemote = getRemote("ShieldActivated")
local waveStateChangedRemote = getRemote("WaveStateChanged")
local upgradeStatRemote = getRemote("UpgradeStat")
local dragonStatsUpdatedRemote = getRemote("DragonStatsUpdated")
local dummyHitRemote = getRemote("DummyHit")
local markLairTutorialSeenRemote = getRemote("MarkLairTutorialSeen")
local bossTelegraphRemote = getRemote("BossTelegraph")
local bossMusicStateRemote = getRemote("BossMusicState")
local bossBannerStateRemote = getRemote("BossBannerState")
local getPlayerDataFunc = getRemoteFunction("GetPlayerData")

-- ================================
-- PLAYER JOIN / LEAVE
-- ================================

local RESPAWN_TIME = 5

-- Build the standard Roblox top-right leaderboard entries for a player.
-- Roblox auto-renders any IntValue/StringValue inside a folder named exactly
-- "leaderstats" under the player. This gives kids the always-visible kill +
-- coin counter they expect from every other Roblox game, no custom UI needed.
local function setupLeaderstats(player: Player, initialCoins: number)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Value = 0
	kills.Parent = leaderstats

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = initialCoins
	coins.Parent = leaderstats
end

-- Keep the leaderboard in sync with round score + coin balance. Called from
-- every place that touches kills/coins. Defensive: silent no-op if the
-- player's leaderstats folder isn't there (very early in join, etc.).
local function refreshLeaderstats(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local killsValue = leaderstats:FindFirstChild("Kills") :: IntValue?
	local coinsValue = leaderstats:FindFirstChild("Coins") :: IntValue?
	if killsValue then
		local board = RoundManager.getScoreboard()
		for _, entry in board do
			if entry.userId == player.UserId then
				killsValue.Value = entry.kills
				break
			end
		end
	end
	if coinsValue then
		coinsValue.Value = DataManager.getCoins(player)
	end
end

-- Sprint 7: helper that pushes the player's current effective stats + upgrade
-- levels for a specific dragon. Called from PlayerAdded (so client caches
-- start populated), SelectDragon (so the new dragon's stats land before
-- combat), and the UpgradeStat handler (so upgrades reflect immediately
-- in the UI + speed cache).
local function fireDragonStatsUpdated(player: Player, dragonId: string)
	local levels = DragonProgression.getLevels(player, dragonId)
	local effective = DragonProgression.getEffectiveStats(player, dragonId)
	dragonStatsUpdatedRemote:FireClient(player, dragonId, levels, effective)
end

-- Sprint 6 playtest fix: was a single inline PlayerAdded handler, now
-- factored into a function + catch-up loop. The bug it fixes: server
-- boot is triggered by the first player joining, but ArenaBuilder.build()
-- and LairBuilder.build() yield on InsertService:LoadAsset for several
-- seconds. By the time PlayerAdded:Connect runs at this line, the firing
-- player joined event has ALREADY been raised — and Roblox doesn't replay
-- it. Result: the boot-trigger player became a ghost (no leaderstats,
-- no DataManager entry, no spawn, no state.scores entry). End-of-round
-- showed "No Winner" / empty leaderboard / 0 coins because the only
-- player had no score record.

-- Idempotency guard. There's a tiny window between Connect and the
-- catch-up loop below where a player joining at exactly that moment
-- could appear in BOTH paths — PlayerAdded fires AND they're already in
-- Players:GetPlayers(). Without this guard, processLogin would
-- double-credit the daily bonus, setupLeaderstats would create a second
-- Folder, etc. Cleared in PlayerRemoving so a rejoin in the same
-- session re-runs init normally.
local processed: { [number]: boolean } = {}

local function processPlayer(player: Player)
	if processed[player.UserId] then return end
	processed[player.UserId] = true

	print(`[Server] {player.Name} joined`)

	-- Load persistent data
	local data = DataManager.loadPlayer(player)
	-- Process daily login: streak update + bonus coins + populate welcomeBonus.
	-- Must run BEFORE the initial UpdateCoins fire so the client sees the new
	-- balance (with the bonus applied). The welcomeBonus payload reaches the
	-- client via the existing GetPlayerData refresh — no new remote needed.
	DataManager.processLogin(player)
	RoundManager.initPlayerScore(player)

	-- Standard leaderboard. Kept in sync with round score + coin balance via
	-- the addCoins / recordKill / recordNPCKill paths below.
	setupLeaderstats(player, data.coins)

	-- Spawn their dragon
	local dragonId = data.selectedDragon
	CombatManager.initPlayer(player, dragonId)
	spawnInLair(player, dragonId)

	-- Send initial data to client (coins now include the daily bonus)
	updateCoinsRemote:FireClient(player, data.coins)
	spawnDragonRemote:FireClient(player, dragonId)
	-- Sprint 7: prime the client's stats cache so FlightController applies
	-- upgraded speed on this very first spawn (without this, the kid would
	-- spawn at the base DragonConfig speed regardless of their +Spd levels
	-- until the first upgrade or dragon switch fires the remote).
	fireDragonStatsUpdated(player, dragonId)
	-- Sprint 9a: kick off the analytics session AFTER PlayerData loaded
	-- and the standard onboarding (leaderstats, spawn) is in place. That
	-- way the SessionStart event has the right player state. markFirstSession
	-- fires only on the kid's actual first-ever join (totalLogins == 1
	-- means processLogin just incremented from 0 → 1).
	Analytics.startSession(player)
	if data.totalLogins == 1 then
		Analytics.markFirstSession(player)
	end
end

Players.PlayerAdded:Connect(processPlayer)
-- Catch any players who joined during the slow build phase. Players
-- already in Players:GetPlayers() won't have triggered the handler we
-- just connected — process them explicitly. task.spawn so we don't
-- block this chunk of init on the (rare) case where multiple players
-- joined very quickly.
for _, player in Players:GetPlayers() do
	task.spawn(processPlayer, player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	print(`[Server] {player.Name} leaving`)
	-- Sprint 9a: end the analytics session BEFORE we tear down the player's
	-- state — the SessionEnd event needs the session record alive to compute
	-- session length. Analytics has its own PlayerRemoving hook as a backstop
	-- for crashes / forgotten cleanup, but explicit-here is cleaner.
	Analytics.endSession(player)
	DataManager.unloadPlayer(player)
	CombatManager.removePlayer(player)
	RoundManager.removePlayerScore(player)
	processed[player.UserId] = nil
end)

-- ================================
-- REMOTE EVENT HANDLERS
-- ================================

-- Dragon selection
selectDragonRemote.OnServerEvent:Connect(function(player: Player, dragonId: unknown)
	if not RateLimiter.check(player, "SelectDragon", 5) then return end
	if typeof(dragonId) ~= "string" then return end
	local id = dragonId :: string

	local data = DataManager.getData(player)
	if not data then return end

	if not DragonConfig[id] then return end
	if not data.unlockedDragons[id] then return end

	data.selectedDragon = id
	CombatManager.initPlayer(player, id)
	spawnInLair(player, id)
	spawnDragonRemote:FireClient(player, id)
	-- Sprint 7: switch dragons → push the new dragon's effective stats
	-- so the client's cache (FlightController speed, HUD level, etc.)
	-- matches the body the player is now flying.
	fireDragonStatsUpdated(player, id)
end)

-- Dragon unlock
unlockDragonRemote.OnServerEvent:Connect(function(player: Player, dragonId: unknown)
	if not RateLimiter.check(player, "UnlockDragon", 2) then return end
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
	-- Sprint 9a: log the unlock for the funnel. viaShop=false because
	-- this is the coin-purchased path; the future Robux "Unlock All
	-- Dragons" pass will fire the same event with viaShop=true.
	Analytics.dragonUnlocked(player, id, dragon.cost, false)
	print(`[Server] {player.Name} unlocked {id}!`)
end)

-- Sprint 7: stat upgrade purchase. The hard work (atomic deduct, per-player
-- race lock, force-save) lives in DragonProgression.tryUpgrade — this
-- handler just rate-limits, validates ownership, dispatches, and broadcasts
-- the result so the client UI + combat state stay in sync.

upgradeStatRemote.OnServerEvent:Connect(function(player: Player, dragonIdRaw: unknown, statKeyRaw: unknown)
	-- 3/sec is plenty — the audit flagged a kid double-clicking the +Atk
	-- button as the realistic abuse vector, not a sustained spam.
	if not RateLimiter.check(player, "UpgradeStat", 3) then
		print(`[UpgradeStat] reject userId={player.UserId}: rate-limited`)
		return
	end
	-- POST-AUDIT FIX: enforce design intent that upgrades only happen at the
	-- Lair Stat Stone. The modal is only opened via the Lair ProximityPrompt,
	-- but a malicious client could call this remote directly mid-Arena —
	-- this gate locks the upgrade flow to the safe zone where it belongs.
	-- Not a security issue (it's the player's own coins), just a design gate.
	if not ZoneManager.isPlayerInLair(player) then
		print(`[UpgradeStat] reject userId={player.UserId}: not in Lair`)
		return
	end
	if typeof(dragonIdRaw) ~= "string" then
		print(`[UpgradeStat] reject userId={player.UserId}: bad dragonId type {typeof(dragonIdRaw)}`)
		return
	end
	if typeof(statKeyRaw) ~= "string" then
		print(`[UpgradeStat] reject userId={player.UserId}: bad statKey type {typeof(statKeyRaw)}`)
		return
	end
	local dragonId = dragonIdRaw :: string
	local statKey = statKeyRaw :: string

	-- Ownership: can't upgrade a dragon you don't own.
	local data = DataManager.getData(player)
	if not data then
		print(`[UpgradeStat] reject userId={player.UserId}: no PlayerData (ghost player?)`)
		return
	end
	if not data.unlockedDragons[dragonId] then
		print(`[UpgradeStat] reject userId={player.UserId}: dragon {dragonId} not unlocked`)
		return
	end

	local success, newLevel, newCoins, errReason = DragonProgression.tryUpgrade(player, dragonId, statKey)
	if not success then
		-- Logged so QA can diagnose from Output console. errReason is one of:
		-- in_flight, no_data, unknown_dragon, unknown_stat, max_level,
		-- not_enough_coins, save_failed.
		print(`[UpgradeStat] reject userId={player.UserId} dragon={dragonId} stat={statKey}: {errReason}`)
		return
	end

	-- Sync coin balance + Roblox top-right leaderstats. The HUD coin display
	-- updates from updateCoinsRemote; leaderstats updates from refreshLeaderstats.
	updateCoinsRemote:FireClient(player, newCoins or 0)
	refreshLeaderstats(player)

	-- Push the new levels + effective stats to the client. Drives:
	--  - DragonUpgradeUI panel (rerender stat row with new level + cost)
	--  - HUD "Lv N" indicator (if upgraded dragon == active dragon)
	--  - FlightController speed cache (if upgraded dragon == active dragon)
	fireDragonStatsUpdated(player, dragonId)

	-- Live combat-state apply: if the upgraded dragon is the kid's active one,
	-- the buff lands immediately — no death/respawn required. Health upgrades
	-- bump maxHealth + heal the delta; damage upgrades affect the next breath.
	-- See CombatManager.applyLiveStatChange.
	--
	-- POST-AUDIT FIX: gate on state.dragonId (what the kid is ACTUALLY flying
	-- right now) instead of data.selectedDragon (their last menu pick).
	-- Race window: between SelectDragon firing and DragonSpawner.spawn
	-- installing the new combat state, selectedDragon is the new dragon
	-- but state.dragonId is still the old one. Using state.dragonId means
	-- live apply only fires when the in-combat reality matches the upgrade.
	local activeState = CombatManager.getState(player)
	if activeState and activeState.dragonId == dragonId then
		CombatManager.applyLiveStatChange(player)
	end

	-- Sprint 9a: log the upgrade event for the funnel. coinsCost computed
	-- from the upgrade cost curve — newLevel is the level we just bought,
	-- so the cost is the (newLevel)th entry in the curve.
	local costCurve = DragonProgression.COST_BY_LEVEL
	local coinsCost = costCurve and costCurve[newLevel] or 0
	Analytics.statUpgraded(player, dragonId, statKey, newLevel or 0, coinsCost)

	print(`[Server] {player.Name} upgraded {dragonId}/{statKey} to lv{newLevel}; coins now {newCoins}`)
end)

-- Sprint 7: idempotent flag flip — first time the kid opens the Stat Stone
-- modal, the client fires this so the "💡 Earn coins by killing..." tutorial
-- hint doesn't replay on rejoin. Force-save so the flag survives a quit.
markLairTutorialSeenRemote.OnServerEvent:Connect(function(player: Player)
	if not RateLimiter.check(player, "MarkLairTutorialSeen", 2) then return end
	local data = DataManager.getData(player)
	if not data then return end
	if data.hasSeenLairTutorial then return end -- already flipped, no-op
	data.hasSeenLairTutorial = true
	DataManager.savePlayer(player)
end)

-- Lock-on relay: client reports its current lock target. Server forwards
-- a brief warning to the targeted player so they know to dodge. We don't
-- track persistent state — each client message is "this is who I'm locked
-- on right now" and we ping the target once. Thrash-spammy clients are
-- self-limited because LockOnController only sends on state changes.
lockOnTargetRemote.OnServerEvent:Connect(function(player: Player, targetUserId: unknown)
	if not RateLimiter.check(player, "LockOnTarget", 10) then return end
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
	if not RateLimiter.check(player, "FireBreath", 5) then return end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	if not CombatManager.canFireBreath(player) then return end

	-- Sprint 5 Part D: no PvP / NPC combat from the Lair.
	-- Sprint 7 carve-out: practice dummies are a valid Lair target so kids
	-- can test their just-purchased upgrades. The carve-out is narrow on
	-- purpose — only the dummy-hit branch runs; the player + NPC paths
	-- below are STILL skipped (the early return below the dummy handler
	-- preserves the safe-zone rule for everything else). Cooldown still
	-- burns on a dummy hit because, from the kid's perspective, they DID
	-- fire their breath — pretending it didn't happen would be confusing.
	-- CombatManager helpers also gate defensively (findHitPlayer /
	-- findPlayersInCone return empty for Lair shooters), so the Lair-only
	-- targeting rule holds even if this branch were edited.
	--
	-- POST-AUDIT FIX: Lair branch runs BEFORE RoundManager.isActive() check.
	-- Why: kids visit the Lair primarily during intermission (port out of
	-- Arena → upgrade → test). The whole "test your new upgrade on the
	-- dummy" promise only lands if the dummy reacts during intermission.
	-- The Arena path below still requires an active round.
	if ZoneManager.isPlayerInLair(player) then
		CombatManager.recordBreath(player)
		local state = CombatManager.getState(player)
		if not state then return end
		-- Same client-origin clamp as the Arena path: snap to server-side
		-- position if the client claims an origin >8 studs from where they
		-- actually are (anti-cheat on dummy damage too — even though dummies
		-- don't reward, an inflated cone could vault past LineOfSight checks
		-- in future and let kids "test" through walls).
		local character = player.Character
		if character and character.PrimaryPart then
			local serverPos = character.PrimaryPart.Position
			if (origin :: Vector3 - serverPos).Magnitude > 8 then
				origin = serverPos
			end
		end
		local dirMag = (direction :: Vector3).Magnitude
		if dirMag < 0.01 or dirMag > 100 then return end

		local hitDummy = LairBuilder.findHitDummy(origin :: Vector3, direction :: Vector3)
		if hitDummy then
			-- Damage uses state.damage (upgrade-aware) so the kid sees their
			-- new attack-stat reflected on the dummy. No falloff, no NPC
			-- callbacks, no scoreboard — purely a feedback loop for testing.
			local newHp = LairBuilder.damageDummy(hitDummy, state.damage)
			-- Tell the shooter so the client can render a floating "-N" above
			-- the dummy. FireClient (not FireAllClients) — others' dummies
			-- don't need our damage spam.
			dummyHitRemote:FireClient(player, hitDummy.part, state.damage, newHp, hitDummy.maxHp)
		end
		return -- preserve the no-PvP/no-NPC rule from Sprint 5 Part D
	end

	-- Arena path requires an active round. Moved here from the top of the
	-- handler so the Lair dummy branch above can run during intermission —
	-- otherwise the "test your upgrade on the dummy" UX breaks at the
	-- exact moment kids want to use it.
	if not RoundManager.isActive() then return end

	CombatManager.recordBreath(player)

	local state = CombatManager.getState(player)
	if not state then return end

	local dragon = DragonConfig[state.dragonId]
	if not dragon then return end

	-- SECURITY: clamp client-supplied origin to within 8 studs of the player's
	-- ACTUAL server-side position. Without this clamp, a cheater can pass
	-- origin = victim_position + small_offset → gets full-damage point-blank
	-- hits from across the map (cone passes, distance-falloff = 1.0).
	-- 8 studs covers the legit ~5-stud breath-muzzle offset CombatInput uses.
	-- If clientOrigin is bogus, we snap to the real character position so the
	-- breath fires from where the cheater actually is — not where they claim.
	local character = player.Character
	if character and character.PrimaryPart then
		local serverPos = character.PrimaryPart.Position
		if (origin :: Vector3 - serverPos).Magnitude > 8 then
			origin = serverPos
		end
	end

	-- Validate direction magnitude to prevent crash from zero-length .Unit calls
	-- and to reject obviously absurd values (cheaters passing huge vectors).
	local dirMag = (direction :: Vector3).Magnitude
	if dirMag < 0.01 or dirMag > 100 then return end

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
		-- Sprint 7: read damage from per-player CombatState (folds in upgrade
		-- bonuses) instead of DragonConfig directly so the kid's Atk-stat
		-- investments actually scale their breath damage.
		local falloffDmg = math.floor(state.damage * CombatManager.distanceFalloff(hitDist))
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
				RoundManager.recordCoins(player, 10) -- count toward end-of-round summary
				updateCoinsRemote:FireClient(player, DataManager.getCoins(player))
				refreshLeaderstats(player)

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
						spawnInLair(hitPlayer, vDragonId)
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
		-- Sprint 7: same upgrade-aware damage source as the player-hit branch.
		local npcFalloffDmg = math.floor(state.damage * CombatManager.distanceFalloff(npcDist))
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
		return
	end

	-- Sprint 10: no NPC hit either — check the active Mega Boss. Same
	-- cone parameters as findHitNPC (dot 0.85 ~ 30deg, range 100). Boss
	-- damage uses state.damage with the same distance falloff so Atk
	-- upgrades flow through to boss DPS. Damage routes to BossManager
	-- (separate state from NPCManager) which tracks per-player
	-- contribution for the commit-5 reward share.
	local hitBoss = BossManager.tryHitWithCone(origin :: Vector3, direction :: Vector3, 0.85, 100)
	if hitBoss then
		CombatManager.recordDamageDealt(player)
		local bossDist = (hitBoss.rootPart.Position - origin :: Vector3).Magnitude
		local bossFalloffDmg = math.floor(state.damage * CombatManager.distanceFalloff(bossDist))
		local bossTravelTime = math.min(bossDist / PROJECTILE_SPEED, TRAVEL_CAP)
		task.delay(bossTravelTime, function()
			if not hitBoss.model or not hitBoss.model.Parent then return end
			BossManager.applyDamage(bossFalloffDmg, player.UserId)
			-- Reuse the DamageNPC remote for visual feedback — client
			-- already renders floating "-N" + Hit sound for any model.
			damageNPCRemote:FireClient(player, hitBoss.model, bossFalloffDmg)
		end)
	end
end)

-- Special ability — all 6 elements implemented.
-- Client now passes camera direction (2nd arg) so cone specials aim where
-- the player is looking, not where the body is tilted (climb/dive/bank).
useSpecialRemote.OnServerEvent:Connect(function(player: Player, clientDirection: unknown)
	if not RateLimiter.check(player, "UseSpecial", 2) then return end
	if not CombatManager.canUseSpecial(player) then return end
	if not RoundManager.isActive() then return end
	-- Sprint 5 Part D: specials are combat tools — disabled in the Lair. We
	-- gate ALL elements (even buff-only specials like Earth armor or Light
	-- heal) so the rule reads cleanly to kids: "the Lair is a safe zone, your
	-- combat keys do nothing here." Cooldown intentionally not burned.
	if ZoneManager.isPlayerInLair(player) then return end

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
		-- Sprint 7: specialDamage folds the Special-stat upgrade into the
		-- vortex's burst. Multiplier of 2 stays — base damage 15 + Special
		-- +25 max gives 80 max vortex damage (was 60 pre-upgrade).
		local fireDmg = state.specialDamage * 2

		local conePlayers = CombatManager.findPlayersInCone(pos, forward, FIRE_CONE_RANGE, FIRE_CONE_DOT, player)
		for _, target in conePlayers do
			CombatManager.recordDamageDealt(player)
			local killed, _ = CombatManager.applyDamage(target, fireDmg)
			damagePlayerRemote:FireAllClients(target.UserId, fireDmg, pos)
			if killed then
				RoundManager.recordKill(player, target)
				DataManager.addCoins(player, 10)
				RoundManager.recordCoins(player, 10) -- count toward end-of-round summary
				updateCoinsRemote:FireClient(player, DataManager.getCoins(player))
				refreshLeaderstats(player)
				playerKORemote:FireAllClients(player.UserId, target.UserId)
				task.delay(RESPAWN_TIME, function()
					if target and target.Parent then
						CombatManager.respawn(target)
						local tData = DataManager.getData(target)
						spawnInLair(target, if tData then tData.selectedDragon else "Ember")
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

		-- Sprint 10: the Fire vortex also hits Blaze if he's in the cone.
		-- Single-target add since there's only ever one Mega Boss.
		local fireBoss = BossManager.tryHitWithCone(pos, forward, FIRE_CONE_DOT, FIRE_CONE_RANGE)
		if fireBoss then
			CombatManager.recordDamageDealt(player)
			BossManager.applyDamage(fireDmg, player.UserId)
			damageNPCRemote:FireClient(player, fireBoss.model, fireDmg)
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
			-- Sprint 7: Lightning's chain damage uses specialDamage so the
			-- Special-stat upgrade scales chain hits. Each link does the
			-- same damage (Storm's special is breadth, not concentrated burst).
			local killed, _ = CombatManager.applyDamage(target, state.specialDamage)
			damagePlayerRemote:FireAllClients(target.UserId, state.specialDamage, pos)
			if killed then
				RoundManager.recordKill(player, target)
				DataManager.addCoins(player, 10)
				RoundManager.recordCoins(player, 10) -- count toward end-of-round summary
				updateCoinsRemote:FireClient(player, DataManager.getCoins(player))
				refreshLeaderstats(player)
				playerKORemote:FireAllClients(player.UserId, target.UserId)
				task.delay(RESPAWN_TIME, function()
					if target and target.Parent then
						CombatManager.respawn(target)
						local tData = DataManager.getData(target)
						spawnInLair(target, if tData then tData.selectedDragon else "Ember")
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
				-- Sprint 7: same upgrade-aware specialDamage source for NPC chain hits.
				NPCManager.applyDamage(npc.id, state.specialDamage, player.UserId)
				damageNPCRemote:FireClient(player, npc.model, state.specialDamage)
			end
		end

		-- Sprint 10: chain can also fork to Blaze if there are slots
		-- left. Treats him as one chain target (not multiple — the
		-- chain is breadth, not concentrated burst).
		if hitCount < 3 then
			local lightningBoss = BossManager.tryHitWithCone(pos, forward, LIGHTNING_CONE_DOT, LIGHTNING_CONE_RANGE)
			if lightningBoss then
				CombatManager.recordDamageDealt(player)
				BossManager.applyDamage(state.specialDamage, player.UserId)
				damageNPCRemote:FireClient(player, lightningBoss.model, state.specialDamage)
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

-- Defensive shield. 12s cooldown, 4s active duration, 80% damage reduction
-- while up. Rate-limited to 2/sec defensively (real cooldown is 12s but the
-- remote spam-guard is cheap insurance). Broadcasts to all clients so
-- everyone sees the shield bubble around the user's dragon.
useShieldRemote.OnServerEvent:Connect(function(player: Player)
	if not RateLimiter.check(player, "UseShield", 2) then return end
	if not CombatManager.canUseShield(player) then return end
	if not RoundManager.isActive() then return end
	-- Sprint 5 Part D: same "no combat in Lair" rule. Shield is technically
	-- defensive but it's still a combat tool, and there's nothing to defend
	-- against in the safe zone. Cooldown not burned so the kid keeps it for
	-- the Arena fight ahead.
	if ZoneManager.isPlayerInLair(player) then return end

	local ok = CombatManager.useShield(player)
	if not ok then return end
	-- Tell everyone the bubble is up so the visual renders for spectators too
	shieldActivatedRemote:FireAllClients(player.UserId)
end)

-- Get player data (RemoteFunction)
getPlayerDataFunc.OnServerInvoke = function(player: Player)
	return DataManager.getData(player)
end

-- ================================
-- ROUND SYSTEM
-- ================================

-- Sprint 6: wave state broadcaster. NPCManager fires this for each
-- wave-state transition so the client WaveTracker HUD can render the
-- right banner / countdown / enemy counter.
local function fireWaveStateChanged(waveNum: number, waveState: string, payload: any)
	waveStateChangedRemote:FireAllClients(waveNum, waveState, payload)
end

-- Sprint 6: wave-clear coin reward. Pays out the per-wave bonus (30/50/100)
-- to every player who participated — alive AND in the Arena (not hiding in
-- the Lair). Lair-hider rule incentivizes engagement: rest in the Lair
-- between waves is fine, but if you skip a wave entirely you don't earn
-- the clear bonus.
local function awardWaveCleared(waveNum: number, coinReward: number)
	for _, player in Players:GetPlayers() do
		if not CombatManager.isAlive(player) then continue end
		if ZoneManager.isPlayerInLair(player) then continue end
		DataManager.addCoins(player, coinReward)
		RoundManager.recordCoins(player, coinReward) -- counts toward end-of-round summary
		updateCoinsRemote:FireClient(player, DataManager.getCoins(player))
		refreshLeaderstats(player)
		-- Sprint 9a: log per-player wave-cleared event. clearTimeSec is
		-- left as 0 here because the wave-clear callback doesn't carry
		-- that data — the wave's clear time lives in the WaveResult that
		-- runWaveSequence returns. Acceptable for MVP since the funnel
		-- only needs the event count + waveNumber dimension.
		-- isBossWave: wave 3 is the existing boss wave per Sprint 6;
		-- Sprint 10 mega-bosses get logged via Analytics.bossDefeated
		-- separately, NOT through this path.
		Analytics.waveCleared(player, waveNum, 0, waveNum == 3)
	end
	print(`[Server] Wave {waveNum} cleared, awarded {coinReward} coins to participants`)
end

-- Per-round wave breakdown captured by onActivePhase, read by onRoundEnd
-- to attach to the roundEndRemote payload. Keyed by nothing — single
-- mutable slot since rounds are sequential. Reset in onRoundStart.
local lastRoundWaveResults: { any } = {}

RoundManager.setCallbacks(
	-- onRoundStart
	function()
		local roundState = RoundManager.getState()
		-- Pass the safety cap (240s) as the round duration so the existing
		-- HUD timer still ticks down to something. The actual round length
		-- is now wave-driven and shorter — this just provides a worst-case
		-- bound for the HUD display.
		roundStartRemote:FireAllClients(roundState.roundNumber, 240)
		-- Reset per-round wave breakdown so onRoundEnd doesn't show stale data.
		lastRoundWaveResults = {}

		-- Respawn all players
		for _, player in Players:GetPlayers() do
			local data = DataManager.getData(player)
			local dragonId = if data then data.selectedDragon else "Ember"
			CombatManager.initPlayer(player, dragonId)
			spawnInLair(player, dragonId)

			if data then
				data.stats.gamesPlayed += 1
			end
		end

		updateScoreboardRemote:FireAllClients(RoundManager.getScoreboard())
	end,

	-- onActivePhase: Sprint 6 wave sequence. Blocks until 3 waves complete
	-- (or until RoundManager's safety-cap forces state.active = false, in
	-- which case runWaveSequence bails out via its isRoundActive() checks).
	-- Returns the per-wave breakdown which we stash for onRoundEnd to send
	-- in the round-end summary payload.
	-- Sprint 10: pass roundNumber so runWaveSequence can detect Mega-
	-- Boss-Rounds (every 3rd round) and append a Blaze encounter after
	-- the standard 3 waves. onBossWarning fires the 30s warning banner.
	function()
		local roundState = RoundManager.getState()
		lastRoundWaveResults = NPCManager.runWaveSequence(
			roundState.roundNumber,
			fireWaveStateChanged,
			RoundManager.isActive,
			awardWaveCleared,
			function(bossType: string, secondsLeft: number)
				bossBannerStateRemote:FireAllClients("WARNING", {
					bossType = bossType,
					secondsLeft = secondsLeft,
				})
			end
		)
	end,

	-- onRoundEnd: award participation + win bonus + first-win-of-day bonus.
	-- Fire RoundEnd with per-player coins-earned data + Sprint 6 per-wave
	-- breakdown so the client can show "you earned X coins" + the wave-by-
	-- wave recap. firstWinClaimed[userId] drives the gold "FIRST WIN TODAY"
	-- highlight.
	function()
		local winner = RoundManager.getWinner()
		local scoreboard = RoundManager.getScoreboard()
		local PARTICIPATION = 5
		local WIN_BONUS = 25

		local coinsEarnedThisRound: { [number]: number } = {}
		local firstWinClaimed: { [number]: boolean } = {}

		for _, player in Players:GetPlayers() do
			-- Start with everything the kid earned during the round (kill
			-- rewards, NPC kill rewards, Sprint 6 wave-clear bonuses). Without
			-- this, the summary used to show "0 coins earned" when the kid
			-- spent the whole round killing NPCs because only post-round
			-- bonuses were counted.
			--
			-- Lair-stayers don't get PARTICIPATION — the safe zone is for
			-- managing your dragon, not earning passively. In-round coins
			-- still count (they'll just be 0 for an AFK Lair camper). The
			-- WIN_BONUS / first-win paths below are unreachable from the
			-- Lair anyway since you can't score kills from there.
			local participation = if ZoneManager.isPlayerInLair(player) then 0 else PARTICIPATION
			local earned = RoundManager.getRoundCoins(player) + participation
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
			-- addCoins only adds the post-round bonuses (participation + win +
			-- first-win) — the in-round earnings were already added live as the
			-- kid scored kills (and via wave-clear payouts). So we add the
			-- delta here, but the DISPLAYED `earned` is the full total
			-- including in-round.
			local postRoundBonus = earned - RoundManager.getRoundCoins(player)
			DataManager.addCoins(player, postRoundBonus)
			coinsEarnedThisRound[player.UserId] = earned
			updateCoinsRemote:FireClient(player, DataManager.getCoins(player))
			refreshLeaderstats(player)
		end

		-- Sprint 9a: log RoundCompleted for every player in the server,
		-- with didWin flag set for the winner only. This is what powers
		-- the "round participation rate" funnel metric. Iterates again
		-- because the loop above was about coin payout — keeping concerns
		-- separate so a future analytics tweak doesn't subtly change
		-- payout math.
		local roundState = RoundManager.getState()
		for _, player in Players:GetPlayers() do
			local didWin = winner ~= nil and winner.UserId == player.UserId
			local kills = 0
			for _, entry in scoreboard do
				if entry.userId == player.UserId then
					kills = entry.kills
					break
				end
			end
			local coinsEarned = coinsEarnedThisRound[player.UserId] or 0
			Analytics.roundCompleted(player, roundState.roundNumber, didWin, kills, coinsEarned)
		end

		roundEndRemote:FireAllClients(
			if winner then winner.UserId else 0,
			scoreboard,
			coinsEarnedThisRound,
			firstWinClaimed,
			lastRoundWaveResults -- Sprint 6: per-wave breakdown for the recap row
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
	-- Track in the round-coin running total so the end-of-round summary
	-- shows the kid's full earnings (was always showing 0 before because
	-- only the +5 participation bonus was being counted).
	RoundManager.recordCoins(killer, coinReward)
	updateCoinsRemote:FireClient(killer, DataManager.getCoins(killer))

	local data = DataManager.getData(killer)
	if data then data.stats.totalKills += 1 end

	-- Count NPC kills toward the round scoreboard too. Kids fighting only
	-- waves were ending rounds with "0 Kills" because PvE wasn't credited
	-- against the round score; this rolls them into the same counter.
	RoundManager.recordNPCKill(killer)
	updateScoreboardRemote:FireAllClients(RoundManager.getScoreboard())
	refreshLeaderstats(killer)

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
				spawnInLair(target, vDragonId)
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

-- H4 fix: pass isRoundActive into the AI loop so it doesn't run during
-- intermission (no wasted ticks, no spectral breath visuals during the
-- 15s dragon-select window). Sprint 6: the wave loop is no longer started
-- here — RoundManager's onActivePhase callback (above) drives waves
-- per-round via NPCManager.runWaveSequence.
NPCManager.startAILoop(npcDamagePlayer, RoundManager.isActive)

-- Sprint 10: BossManager AI tick callbacks. damageCallback reuses
-- npcDamagePlayer so boss attacks flow through the same path as
-- regular NPC damage (CombatManager.applyDamage, KO handling,
-- respawn timing) — keeps boss-vs-player damage consistent with
-- everything else. telegraphCallback fires the BossTelegraph remote
-- to all clients so the BossTelegraph.luau client renderer can draw
-- the slam circle / beam preview.
-- Sprint 10 commit 6: boss-spawned signal. Fires the BLAZE APPEARS
-- banner state + boss music swap to all clients. Analytics fires
-- per-player BossEncountered for everyone in the server.
BossManager.setOnSpawnedCallback(function(bossType: string, maxHealth: number)
	bossBannerStateRemote:FireAllClients("INCOMING", { bossType = bossType, maxHealth = maxHealth })
	bossMusicStateRemote:FireAllClients(true)
	-- Analytics: lights up the BossEncountered event scaffolded in
	-- Sprint 9a. Fires for every player in the server (including
	-- Lair-stayers — they SAW the encounter happen via the banner).
	local roundState = RoundManager.getState()
	for _, player in Players:GetPlayers() do
		Analytics.bossEncountered(player, bossType, roundState.roundNumber)
	end
	print(`[Server] {bossType} spawned with {maxHealth} HP — banner + music fired`)
end)

BossManager.setDamageCallback(function(target: Player, damage: number, source: Vector3)
	-- Lair-hider gate (defense-in-depth): a kid sitting in the Lair
	-- when Blaze swings shouldn't take damage. Sprint 5 Part D's
	-- CombatManager.applyDamage already refuses Lair targets, but
	-- explicit-here means we skip the per-attack damage broadcast
	-- entirely instead of doing the work and discarding the result.
	if ZoneManager.isPlayerInLair(target) then return end
	npcDamagePlayer(target, damage, source, nil, nil)
end)
BossManager.setTelegraphCallback(function(attackType: string, originPos: Vector3, directionOrRadius: Vector3, windupSec: number)
	bossTelegraphRemote:FireAllClients(attackType, originPos, directionOrRadius, windupSec)
end)

-- Sprint 10 commit 5: boss death + reward distribution.
-- Reward formula (peer audit): 50 flat participation + 300 damage-share.
-- Solo player: 50 + 300 = 350 coins. 4-player team each: 50 + ~75 = ~125.
-- The flat bonus protects new-kid feel-bad; the share rewards effort.
-- Players who left mid-fight have their share dropped silently
-- (Players:GetPlayerByUserId returns nil → skip); the pool isn't
-- redistributed to the remaining players (keeps math simple).
local BOSS_FLAT_PARTICIPATION = 50
local BOSS_SHARE_POOL = 300

BossManager.setOnDefeatCallback(function(bossType: string, contributions: { [number]: number }, totalDamage: number)
	local roundState = RoundManager.getState()
	for userId, contribDmg in contributions do
		local player = Players:GetPlayerByUserId(userId)
		if not player then continue end -- left server mid-fight; their share is forfeit
		local share = if totalDamage > 0 then math.floor((contribDmg / totalDamage) * BOSS_SHARE_POOL) else 0
		local payout = BOSS_FLAT_PARTICIPATION + share
		DataManager.addCoins(player, payout)
		RoundManager.recordCoins(player, payout) -- counts toward end-of-round summary
		updateCoinsRemote:FireClient(player, DataManager.getCoins(player))
		refreshLeaderstats(player)
		-- Persistent bragging-rights stat (Sprint 10 PlayerData addition).
		-- Increment for any kid who damaged Blaze before death — they
		-- "defeated" him collectively even if they didn't deal the kill blow.
		local data = DataManager.getData(player)
		if data and data.stats then
			data.stats.bossesDefeated = (data.stats.bossesDefeated or 0) + 1
		end
		-- Analytics: lights up the BossDefeated event (scaffolded in
		-- Sprint 9a). damageContribution and coinReward dimensions feed
		-- the dashboard's "boss DPS distribution" + "boss reward
		-- distribution" charts.
		Analytics.bossDefeated(player, bossType, roundState.roundNumber, contribDmg, payout)
	end
	-- Banner: "BLAZE FALLS" celebration. Commit 6 wires the client
	-- WaveTracker handler that renders this state.
	bossBannerStateRemote:FireAllClients("DEFEATED", { bossType = bossType })
	-- Music: revert to zone music. Active=false signals the client
	-- LairAtmosphere/SoundManager pair to restore the pre-encounter
	-- music state.
	bossMusicStateRemote:FireAllClients(false)
	-- Hold the death-pose model for a moment before despawning so kids
	-- see the boss go down rather than vanishing instantly. 2 seconds
	-- matches the wave-clear celebration window.
	task.delay(2, function()
		BossManager.despawn()
	end)
	print(`[Server] {bossType} defeated; awarded {BOSS_FLAT_PARTICIPATION} flat + {BOSS_SHARE_POOL} share across {totalDamage} total damage`)
end)

BossManager.setOnTimeoutCallback(function(bossType: string, hpRemainingPercent: number)
	-- No reward distribution by design (peer audit: failure → learning
	-- loop). Analytics fires for each kid who DID damage the boss so
	-- the dashboard can show "engaged but failed" vs. "didn't engage."
	local roundState = RoundManager.getState()
	for userId in BossManager.getDamageContributions() do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			Analytics.bossTimedOut(player, bossType, roundState.roundNumber, hpRemainingPercent)
		end
	end
	-- Banner: "BLAZE ESCAPES" — kid sees their failure clearly. Commit
	-- 6 wires the client WaveTracker handler.
	bossBannerStateRemote:FireAllClients("TIMEOUT", { bossType = bossType, hpRemainingPercent = hpRemainingPercent })
	bossMusicStateRemote:FireAllClients(false)
	print(`[Server] {bossType} timed out at {math.floor(hpRemainingPercent * 100)}% HP remaining`)
end)

-- ================================
-- Sprint 5 Part E: PORTAL TELEPORTS
-- ================================
-- Lair portal (tag "DragonWarz_Portal_ToArena") teleports the toucher
-- to a random Arena spawn point. Per-player cooldown via attribute
-- prevents the touch-loop bounce-back when the player overlaps the
-- portal post-teleport.
local PORTAL_COOLDOWN = 2 -- seconds between teleports per player

local function bindPortal(portal: BasePart, teleportFn: (Player) -> ())
	portal.Touched:Connect(function(otherPart: BasePart)
		local character = otherPart:FindFirstAncestorOfClass("Model")
		if not character then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		-- Per-player cooldown to prevent infinite bounce
		local key = `LastTeleport_{player.UserId}`
		local last = portal:GetAttribute(key) or 0
		if tick() - last < PORTAL_COOLDOWN then return end
		portal:SetAttribute(key, tick())
		teleportFn(player)
	end)
end

-- Wire all existing tagged portals + future ones (in case of respawn/rebuild)
for _, portal in CollectionService:GetTagged("DragonWarz_Portal_ToArena") do
	bindPortal(portal :: BasePart, teleportToArena)
end
CollectionService:GetInstanceAddedSignal("DragonWarz_Portal_ToArena"):Connect(function(portal)
	bindPortal(portal :: BasePart, teleportToArena)
end)

for _, portal in CollectionService:GetTagged("DragonWarz_Portal_ToLair") do
	bindPortal(portal :: BasePart, teleportToLair)
end
CollectionService:GetInstanceAddedSignal("DragonWarz_Portal_ToLair"):Connect(function(portal)
	bindPortal(portal :: BasePart, teleportToLair)
end)

print("[Server] Dragon Warz server ready! (with NPC survival system + portals)")
