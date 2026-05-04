--!strict
-- NPC Manager: server-authoritative AI dragon enemies for survival gameplay.
--
-- Architecture:
-- - Each NPC is a Model in workspace (NOT tied to a Player object)
-- - Tagged with "DragonWarz_NPC" CollectionService tag for client identification
-- - Server runs a fixed-rate AI tick (~5Hz) that updates all NPC behaviors:
--   target acquisition → chase → fire breath when in range
-- - Wave system: spawns scale up over the round (more enemies, harder tiers)
-- - Combat: NPCs both deal and take damage via the same hit-detection path
--   used for players, but with separate state tables to avoid Player object
--   coupling
--
-- Why server-authoritative AI:
-- - Cheating: clients must NOT control enemy positions/damage
-- - Consistency: every player sees the same NPC behavior
-- - Performance: ~10-15 NPCs at 5Hz is trivial server load

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local EnemyConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("EnemyConfig"))
local ZoneManager = require(script.Parent.ZoneManager)
local BossManager = require(script.Parent.BossManager)

local NPCManager = {}

-- Per-NPC runtime state. Keyed by a unique numeric id (separate namespace
-- from Player.UserId so we never collide).
export type NPCState = {
	id: number,
	enemyType: string, -- "Scout" | "Warrior" | "Boss"
	model: Model,
	rootPart: BasePart,
	linearVelocity: LinearVelocity,
	alignOrientation: AlignOrientation,
	health: number,
	maxHealth: number,
	alive: boolean,
	-- AI state
	targetUserId: number?, -- nil = no target; switches to nearest player when in range
	lastBreathTime: number,
	wanderTarget: Vector3,
	wanderRetargetAt: number,
}

local npcs: { [number]: NPCState } = {}
local nextNpcId = 1
local AI_TICK_RATE = 0.2 -- seconds; 5Hz AI updates (smooth enough to feel reactive, cheap)

-- Sprint 6: 3-wave structure with rest periods. Replaces the old
-- continuous-spawn loop. Each round has exactly three waves:
--   1. Easy onramp (scouts only) — kids learn the controls
--   2. Medium (scouts + warrior) — teaches them about tougher enemies
--   3. Boss + minions — climactic moment, the round ends right here
-- Why three waves: rest periods (15s between) give the kid a breather,
-- and three is enough beats to feel structure without dragging.
local WAVE_DEFS = {
	{ scouts = 3, warriors = 0, bosses = 0, isBoss = false, coinReward = 30 }, -- wave 1: easy
	{ scouts = 4, warriors = 1, bosses = 0, isBoss = false, coinReward = 50 }, -- wave 2: medium
	{ scouts = 2, warriors = 0, bosses = 1, isBoss = true,  coinReward = 100 }, -- wave 3: boss
}

local NUM_WAVES = #WAVE_DEFS

-- Sprint 10: Mega-Boss-Round cadence. Every Nth round, after the
-- standard NUM_WAVES finish, an additional "Mega Boss" wave runs where
-- BossManager.spawnBlaze spawns BLAZE THE INFERNO LORD. Cadence of 3
-- means rounds 3, 6, 9, ... are Mega-Boss-Rounds — peer audit settled
-- on this rhythm: ~6-9 minutes between encounters with the existing
-- ~3-min round length.
local MEGA_BOSS_CADENCE = 3
-- Total fight window before the boss is force-despawned with no
-- rewards. 90 seconds gives kids ~60 seconds of actual fighting plus
-- a 30-second warning window ("BOSS ESCAPING IN 30s") which commit 6
-- surfaces in the WaveTracker banner. Boss-death exits the loop
-- earlier; boss timeout = boss "escapes," kids who failed get nothing
-- (peer audit guidance — failure → learning loop).
local MEGA_BOSS_FIGHT_DURATION = 90
local MEGA_BOSS_WARNING_THRESHOLD = 30 -- "ESCAPING IN 30s" fires at this remaining

-- Wave-flow timings. INCOMING is the telegraph window where the banner
-- shows but no enemies have spawned yet — gives the kid 3 seconds to
-- mentally prepare. WAVE_TIMEOUT is the safety cap: if the kid can't
-- (or won't) kill all the NPCs in 90 seconds the wave force-ends so
-- the round can advance. REST_DURATION is the breather between waves.
local WAVE_INCOMING_DURATION = 3
local WAVE_TIMEOUT = 90
local REST_DURATION = 15
local WAVE_TICK_RATE = 0.5 -- how often to broadcast enemiesLeft updates during ACTIVE

-- Wave state strings — match the union the client switches on.
local STATE_INCOMING = "INCOMING"
local STATE_ACTIVE = "ACTIVE"
local STATE_CLEARED = "CLEARED"
local STATE_TIMEOUT = "TIMEOUT"
local STATE_RESTING = "RESTING"

-- Soft cap on simultaneous NPCs. Past this, new spawns are skipped to keep
-- server perf reasonable. Bosses count toward this same cap.
local MAX_NPCS = 12

-- Spawn perimeter: NPCs spawn at the edge of the arena and fly inward, so
-- they appear to "arrive" rather than materialize on top of players.
local SPAWN_RADIUS = 250
local SPAWN_HEIGHT_RANGE = { min = 40, max = 120 }

-- Mesh template cache (same pattern as DragonSpawner — only download once)
local meshCache: { [string]: Model } = {}

-- Callback set by init.server.luau for awarding coins on NPC kills + firing
-- the kill feed remote.
local onNpcKilledCallback: ((killerUserId: number, enemyType: string, coinReward: number) -> ())?

function NPCManager.setKillCallback(callback: (number, string, number) -> ())
	onNpcKilledCallback = callback
end

-- Callback fired when an NPC's AI acquires a NEW player target (was nil or
-- different player previously). Lets server warn the locked player.
-- Rate-limiting happens on the receiver (init.server.luau) so multiple
-- NPCs targeting the same player don't spam warnings.
local onNpcAcquiredTargetCallback: ((playerUserId: number, enemyName: string) -> ())?

function NPCManager.setLockOnCallback(callback: (number, string) -> ())
	onNpcAcquiredTargetCallback = callback
end

-- Same loadMeshTemplate pattern as DragonSpawner. Returns a fresh clone or
-- nil on failure (caller falls back to placeholder parts).
local function loadMeshTemplate(enemyType: string, assetId: number): Model?
	if meshCache[enemyType] then
		return meshCache[enemyType]:Clone()
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not result then
		warn(`[NPCManager] Failed to load mesh for {enemyType} (assetId={assetId}): {result}`)
		return nil
	end
	local container = result :: Model
	local meshContent: Model? = nil
	for _, child in container:GetChildren() do
		if child:IsA("Model") then
			meshContent = child
			break
		end
	end
	if not meshContent then
		meshContent = container
	end
	meshCache[enemyType] = meshContent :: Model
	container.Parent = nil
	return (meshContent :: Model):Clone()
end

-- Build a placeholder enemy model: a colored box with attached Humanoid.
-- Used when mesh loading fails or for visual variety on Scout tier.
local function buildPlaceholderModel(enemy: any, enemyName: string): Model
	local model = Instance.new("Model")
	model.Name = enemyName

	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Size = Vector3.new(6 * enemy.scale, 4 * enemy.scale, 10 * enemy.scale)
	body.Color = enemy.color
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = false
	body.CanCollide = false -- phases through players; avoids the stuck-on-each-other dance
	-- Body must NOT be massless. Roblox physics treats zero-mass assemblies as
	-- immovable — LinearVelocity silently does nothing. (Wings/mesh parts stay
	-- massless because they're welded to the body, which now has the assembly mass.)
	body.Parent = model

	-- Wing visuals — give the enemy *some* dragon-shape recognition
	local wingL = Instance.new("Part")
	wingL.Name = "WingLeft"
	wingL.Size = Vector3.new(8 * enemy.scale, 0.5, 5 * enemy.scale)
	wingL.Color = enemy.secondaryColor
	wingL.Material = Enum.Material.SmoothPlastic
	wingL.CanCollide = false
	wingL.Massless = true
	wingL.Parent = model
	local wlw = Instance.new("WeldConstraint")
	wlw.Part0 = body
	wlw.Part1 = wingL
	wlw.Parent = wingL
	wingL.CFrame = body.CFrame * CFrame.new(-7 * enemy.scale, 1, 0)

	local wingR = wingL:Clone()
	wingR.Name = "WingRight"
	wingR.Parent = model
	local wrw = Instance.new("WeldConstraint")
	wrw.Part0 = body
	wrw.Part1 = wingR
	wrw.Parent = wingR
	wingR.CFrame = body.CFrame * CFrame.new(7 * enemy.scale, 1, 0)

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = enemy.health
	humanoid.Health = enemy.health
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.Parent = model

	model.PrimaryPart = body
	return model
end

-- Attach trail effect (same pattern as DragonSpawner, but the enemy color)
local function attachTrail(model: Model, enemy: any)
	local body = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not body then return end
	local frontAttach = Instance.new("Attachment")
	frontAttach.Name = "TrailFront"
	frontAttach.Position = Vector3.new(0, 0, 2)
	frontAttach.Parent = body
	local backAttach = Instance.new("Attachment")
	backAttach.Name = "TrailBack"
	backAttach.Position = Vector3.new(0, 0, -2)
	backAttach.Parent = body
	local trail = Instance.new("Trail")
	trail.Attachment0 = frontAttach
	trail.Attachment1 = backAttach
	trail.Lifetime = 1.0
	trail.MinLength = 0.05
	trail.LightEmission = 0.6
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Color = ColorSequence.new(enemy.color, enemy.secondaryColor)
	trail.Parent = body
end

-- Attach a Meshy mesh as visual layer to the placeholder body. Mirrors
-- DragonSpawner.attachMeshVisual but with simpler architecture (no Motor6D
-- needed since NPCs don't have player-controlled wobble).
local function attachMeshVisual(model: Model, enemyType: string, assetId: number, scale: number)
	local meshTemplate = loadMeshTemplate(enemyType, assetId)
	if not meshTemplate then return end

	local body = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not body then return end

	-- Hide placeholder visuals so the mesh shows alone
	for _, partName in { "HumanoidRootPart", "WingLeft", "WingRight" } do
		local part = model:FindFirstChild(partName) :: BasePart?
		if part then
			part.Transparency = 1
		end
	end

	if meshTemplate:IsA("Model") then
		meshTemplate:ScaleTo(scale)
		meshTemplate:PivotTo(body.CFrame)
	end
	meshTemplate.Name = "EnemyMesh"
	meshTemplate.Parent = model

	for _, descendant in meshTemplate:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
end

-- Pick a random spawn position on the arena perimeter.
-- Spawning from edges means players see them coming, not "they appeared on me".
local function randomSpawnPosition(): Vector3
	local angle = math.random() * math.pi * 2
	local x = math.cos(angle) * SPAWN_RADIUS
	local z = math.sin(angle) * SPAWN_RADIUS
	local y = math.random(SPAWN_HEIGHT_RANGE.min, SPAWN_HEIGHT_RANGE.max)
	return Vector3.new(x, y, z)
end

-- Pick a random wander target near the arena center (NPCs without a target
-- drift around the play area instead of standing still or wandering offscreen).
local function randomWanderTarget(): Vector3
	return Vector3.new(
		math.random(-150, 150),
		math.random(50, 100),
		math.random(-150, 150)
	)
end

function NPCManager.spawn(enemyType: string): NPCState?
	if #NPCManager.getAlive() >= MAX_NPCS then
		print(`[NPCManager] At cap ({MAX_NPCS}), skipping spawn of {enemyType}`)
		return nil
	end

	local enemy = EnemyConfig[enemyType]
	if not enemy then
		warn(`[NPCManager] Unknown enemy type: {enemyType}`)
		return nil
	end

	local id = nextNpcId
	nextNpcId += 1

	local model = buildPlaceholderModel(enemy, `{enemy.name}_{id}`)
	local spawnPos = randomSpawnPosition()
	model:PivotTo(CFrame.new(spawnPos))
	model.Parent = workspace
	print(`[NPCManager] Spawned {enemy.name} #{id} at {spawnPos}`)

	-- Tag for client-side identification (e.g., enemy nameplate styling)
	CollectionService:AddTag(model, "DragonWarz_NPC")
	model:SetAttribute("EnemyType", enemyType)

	-- Optional Meshy visual
	if enemy.meshAssetId then
		attachMeshVisual(model, enemyType, enemy.meshAssetId, enemy.meshScale or 1)
	end

	attachTrail(model, enemy)

	-- Nameplate showing enemy type + tier
	local rootPart = model.PrimaryPart :: BasePart
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.fromOffset(180, 50)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.Adornee = rootPart
	billboard.Parent = model
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.7)
	label.BackgroundTransparency = 1
	label.Text = enemy.name
	label.TextColor3 = enemy.color
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboard
	local tierLabel = Instance.new("TextLabel")
	tierLabel.Size = UDim2.fromScale(1, 0.3)
	tierLabel.Position = UDim2.fromScale(0, 0.7)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Text = enemy.tier:upper()
	tierLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
	tierLabel.TextStrokeTransparency = 0
	tierLabel.Font = Enum.Font.GothamBlack
	tierLabel.TextScaled = true
	tierLabel.Parent = billboard

	-- Health bar (so players can see how close to killing)
	local hpGui = Instance.new("BillboardGui")
	hpGui.Name = "HealthBar"
	hpGui.Size = UDim2.fromOffset(150, 12)
	hpGui.StudsOffset = Vector3.new(0, 4, 0)
	hpGui.Adornee = rootPart
	hpGui.Parent = model
	local hpBg = Instance.new("Frame")
	hpBg.Size = UDim2.fromScale(1, 1)
	hpBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	hpBg.BorderSizePixel = 0
	hpBg.Parent = hpGui
	local hpFill = Instance.new("Frame")
	hpFill.Name = "Fill"
	hpFill.Size = UDim2.fromScale(1, 1)
	hpFill.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBg

	-- Flight constraints (same as player dragons)
	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = rootPart

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "FlightVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = math.huge
	linearVelocity.VectorVelocity = Vector3.zero
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.Parent = rootPart

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "FlightGyro"
	alignOrientation.Attachment0 = attachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.MaxTorque = math.huge
	alignOrientation.Responsiveness = 15
	alignOrientation.CFrame = CFrame.new(spawnPos)
	alignOrientation.Parent = rootPart

	local state: NPCState = {
		id = id,
		enemyType = enemyType,
		model = model,
		rootPart = rootPart,
		linearVelocity = linearVelocity,
		alignOrientation = alignOrientation,
		health = enemy.health,
		maxHealth = enemy.health,
		alive = true,
		targetUserId = nil,
		lastBreathTime = 0,
		wanderTarget = randomWanderTarget(),
		wanderRetargetAt = tick() + math.random(5, 10),
	}
	npcs[id] = state
	return state
end

function NPCManager.despawn(id: number)
	local state = npcs[id]
	if not state then return end
	if state.model and state.model.Parent then
		state.model:Destroy()
	end
	npcs[id] = nil
end

function NPCManager.getAlive(): { NPCState }
	local result: { NPCState } = {}
	for _, state in npcs do
		if state.alive then
			table.insert(result, state)
		end
	end
	return result
end

-- Called by CombatManager when a player's breath attack hits an NPC.
-- Returns (killed: boolean, actualDamage: number).
function NPCManager.applyDamage(npcId: number, damage: number, killerUserId: number?): (boolean, number)
	local state = npcs[npcId]
	if not state or not state.alive then
		return false, 0
	end

	state.health = math.max(0, state.health - damage)

	-- Update health bar visual
	local hpGui = state.model:FindFirstChild("HealthBar") :: BillboardGui?
	if hpGui then
		local hpBg = hpGui:FindFirstChildOfClass("Frame")
		if hpBg then
			local hpFill = hpBg:FindFirstChild("Fill") :: Frame?
			if hpFill then
				hpFill.Size = UDim2.fromScale(state.health / state.maxHealth, 1)
			end
		end
	end

	if state.health <= 0 then
		state.alive = false

		-- Award the killer
		if killerUserId and onNpcKilledCallback then
			local enemy = EnemyConfig[state.enemyType]
			if enemy then
				onNpcKilledCallback(killerUserId, state.enemyType, enemy.coinReward)
			end
		end

		-- M1 fix: stop the corpse from drifting + disable the trail so it
		-- doesn't keep streaming particles for the 500ms death-visible delay.
		state.linearVelocity.VectorVelocity = Vector3.zero
		local trail = state.rootPart:FindFirstChildOfClass("Trail")
		if trail then trail.Enabled = false end

		-- Destroy after short delay so the death is visible
		task.delay(0.5, function()
			NPCManager.despawn(state.id)
		end)
		return true, damage
	end

	-- Aggro on the killer (so a passing player can't shoot once and ignore the response)
	if killerUserId then
		state.targetUserId = killerUserId
	end
	return false, damage
end

-- Find the nearest alive player within `range` of `pos`. Returns nil if none.
-- Sprint 5 Part D: Lair players are invisible to NPC AI. They're in the safe
-- zone, so they shouldn't get acquired as a target even if technically within
-- detection range (could happen if a Lair-edge wanderer scrapes the radius
-- of a high-altitude Boss).
local function findNearestPlayer(pos: Vector3, range: number): Player?
	local best: Player? = nil
	local bestDist = range
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		if char and char.PrimaryPart then
			if not ZoneManager.isPlayerInLair(plr) then
				local dist = (char.PrimaryPart.Position - pos).Magnitude
				if dist < bestDist then
					bestDist = dist
					best = plr
				end
			end
		end
	end
	return best
end

-- AI tick: runs every AI_TICK_RATE seconds, updates all NPCs.
-- Damage callback signature: (target, damage, source, npcModel, color) — the
-- last two are for the H2 fix (broadcast breath visual on the client).
local function tickAI(damageCallback: (target: Player, damage: number, source: Vector3, npcModel: Model?, color: Color3?) -> ())
	local now = tick()

	for id, state in npcs do
		if not state.alive then
			continue
		end

		local enemy = EnemyConfig[state.enemyType]
		if not enemy then continue end

		local pos = state.rootPart.Position

		-- Re-acquire target every tick so they switch to closer players when relevant.
		-- Aggro persistence is preserved: if current target still in detection range,
		-- keep them; otherwise look for a new one.
		-- Sprint 5 Part D: also drop the target if they portal into the Lair
		-- mid-chase (the safe zone breaks aggro the moment they cross over).
		local currentTarget: Player? = nil
		if state.targetUserId then
			currentTarget = Players:GetPlayerByUserId(state.targetUserId)
			if currentTarget and currentTarget.Character and currentTarget.Character.PrimaryPart then
				local dist = (currentTarget.Character.PrimaryPart.Position - pos).Magnitude
				if dist > enemy.detectionRange * 1.5 then -- 50% leash extension before drop
					currentTarget = nil
					state.targetUserId = nil
				elseif ZoneManager.isPlayerInLair(currentTarget) then
					currentTarget = nil
					state.targetUserId = nil
				end
			else
				currentTarget = nil
				state.targetUserId = nil
			end
		end

		if not currentTarget then
			currentTarget = findNearestPlayer(pos, enemy.detectionRange)
			if currentTarget then
				state.targetUserId = currentTarget.UserId
				-- Newly acquired target — warn the player. Receiver
				-- rate-limits so multiple NPCs targeting the same player
				-- don't stack into a stuttering siren.
				if onNpcAcquiredTargetCallback then
					onNpcAcquiredTargetCallback(currentTarget.UserId, enemy.name)
				end
			end
		end

		if currentTarget and currentTarget.Character and currentTarget.Character.PrimaryPart then
			-- CHASE: fly toward target, slightly above so we maintain altitude
			local targetPos = currentTarget.Character.PrimaryPart.Position
			local toTarget = targetPos - pos
			local dist = toTarget.Magnitude

			if dist > 0.1 then
				-- Move at enemy speed, but back off slightly when within attack range
				-- so they orbit instead of crash-landing into the player.
				local moveSpeed = enemy.speed
				local moveDir = toTarget.Unit
				if dist < enemy.attackRange * 0.7 then
					moveSpeed *= 0.3 -- hover when up close, less zigzagging
				end
				state.linearVelocity.VectorVelocity = moveDir * moveSpeed

				-- Face the target (CFrame.lookAt is the modern, non-deprecated form)
				state.alignOrientation.CFrame = CFrame.lookAt(pos, targetPos)

				-- ATTACK: fire breath if in range and cooldown elapsed.
				-- H2: pass NPC model + color so the damage callback can broadcast
				-- a visible projectile to all clients.
				if dist < enemy.attackRange and (now - state.lastBreathTime) >= enemy.attackCooldown then
					state.lastBreathTime = now
					damageCallback(currentTarget, enemy.damage, pos, state.model, enemy.color)
				end
			end
		else
			-- WANDER: drift toward wanderTarget, retarget periodically
			if now > state.wanderRetargetAt then
				state.wanderTarget = randomWanderTarget()
				state.wanderRetargetAt = now + math.random(8, 15)
			end
			local toWander = state.wanderTarget - pos
			if toWander.Magnitude > 5 then
				state.linearVelocity.VectorVelocity = toWander.Unit * (enemy.speed * 0.5)
				state.alignOrientation.CFrame = CFrame.lookAt(pos, state.wanderTarget)
			else
				state.linearVelocity.VectorVelocity = Vector3.zero
			end
		end
	end
end

-- Public: start AI tick loop. Call once on server startup.
-- H4: optional isRoundActive gate so the AI doesn't burn cycles or fire
-- spectral breath visuals during the 15s intermission.
-- M6: pcall errors now logged instead of silently dropped.
function NPCManager.startAILoop(
	damageCallback: (target: Player, damage: number, source: Vector3, npcModel: Model?, color: Color3?) -> (),
	isRoundActive: (() -> boolean)?
)
	task.spawn(function()
		while true do
			task.wait(AI_TICK_RATE)
			if isRoundActive and not isRoundActive() then
				continue
			end
			local ok, err = pcall(tickAI, damageCallback)
			if not ok then
				warn(`[NPCManager] AI tick error: {err}`)
			end
		end
	end)
end

-- Sprint 6: structured wave sequence. Replaces the old startWaveLoop's
-- continuous chaos with a deterministic 3-wave rhythm.
--
-- Per round, this runs ONCE: wave 1 → rest → wave 2 → rest → wave 3
-- → done. Returns to the caller (RoundManager) when the sequence is
-- complete so the round-end flow can fire the summary etc.
--
-- State machine per wave:
--   INCOMING  — 3-second telegraph (banner shown, no spawns yet)
--   ACTIVE    — NPCs spawned, fighting; broadcast enemiesLeft on every kill
--   CLEARED   — all NPCs killed within timeout; pay coin reward
--   TIMEOUT   — 90s hit with NPCs still alive; force-clear, no bonus
--   RESTING   — 15s breather (skipped after the boss wave; round ends)
--
-- Callers pass three callbacks:
--   fireWaveState(waveNum, state, payload)  — broadcast UI signal
--   isRoundActive()                          — bail-out check
--   onWaveCleared(waveNum, coinReward)       — per-wave reward distribution
--
-- Returns the per-wave breakdown table for the round-end summary:
--   { { waveNum = 1, status = "CLEARED", clearTime = 22.4 }, ... }

-- Per-wave result, passed back to RoundManager → roundEndRemote so the
-- end-of-round summary can render a wave-by-wave breakdown row.
export type WaveResult = {
	waveNum: number,
	status: string, -- "CLEARED" | "TIMEOUT" | "ABORTED"
	clearTime: number?, -- nil for TIMEOUT/ABORTED
	isBossWave: boolean,
}

-- Internal: count alive NPCs cheaply (no allocation). Used in the ACTIVE
-- phase polling loop to decide when the wave is cleared.
local function countAliveNPCs(): number
	local n = 0
	for _, state in npcs do
		if state.alive then n += 1 end
	end
	return n
end

-- Sprint 10: roundNumber added as first parameter so the wave loop
-- can detect Mega-Boss-Rounds (every MEGA_BOSS_CADENCE rounds) and
-- append a boss wave after the standard NUM_WAVES. RoundManager has
-- the canonical round number; init.server.luau passes it through.
function NPCManager.runWaveSequence(
	roundNumber: number,
	fireWaveState: (waveNum: number, state: string, payload: any) -> (),
	isRoundActive: () -> boolean,
	onWaveCleared: (waveNum: number, coinReward: number) -> ()
): { WaveResult }
	local results: { WaveResult } = {}

	for waveNum = 1, NUM_WAVES do
		if not isRoundActive() then
			table.insert(results, { waveNum = waveNum, status = "ABORTED", clearTime = nil, isBossWave = WAVE_DEFS[waveNum].isBoss })
			break
		end

		local waveDef = WAVE_DEFS[waveNum]
		print(`[NPCManager] Wave {waveNum} INCOMING (boss={waveDef.isBoss})`)

		-- INCOMING: telegraph window. Client shows "WAVE X INCOMING" banner
		-- so the kid has 3 seconds to position before NPCs appear.
		fireWaveState(waveNum, STATE_INCOMING, { isBossWave = waveDef.isBoss })
		for _ = 1, WAVE_INCOMING_DURATION do
			if not isRoundActive() then break end
			task.wait(1)
		end
		if not isRoundActive() then
			table.insert(results, { waveNum = waveNum, status = "ABORTED", clearTime = nil, isBossWave = waveDef.isBoss })
			break
		end

		-- SPAWN + ACTIVE: kick off the NPCs (concurrent with ACTIVE state)
		-- and broadcast the initial enemy count. The ACTIVE loop polls every
		-- WAVE_TICK_RATE seconds and re-broadcasts so the client counter ticks
		-- down without needing per-kill remotes.
		--
		-- Closure-captured state lets the broadcast count "remaining to kill"
		-- correctly during the spawn-stagger window. Without this, the kid
		-- would see counter weirdness: spawn 1 → "1 / 5" → kill it → "0 / 5"
		-- (looks done) → spawn 2 → "2 / 5" (counter went UP). The trick is to
		-- compute enemiesLeft as `alive + (intended - spawnedCount)` while
		-- spawning is in progress: NPCs not yet spawned are counted as
		-- still-needs-killing, so the numerator only ever decreases on a kill.
		--
		-- spawnDone is the source of truth for "wave cleared" so we never
		-- false-clear during the stagger window. Replaces the previous
		-- `elapsed > 2` band-aid which broke if a max-stat dragon blitzed
		-- the early Scouts before the Warrior had spawned.
		local totalEnemies = waveDef.scouts + waveDef.warriors + waveDef.bosses
		local spawnedCount = 0
		local spawnDone = false

		task.spawn(function()
			for _ = 1, waveDef.scouts do
				if not isRoundActive() then break end
				if NPCManager.spawn("Scout") then spawnedCount += 1 end
				task.wait(0.3)
			end
			for _ = 1, waveDef.warriors do
				if not isRoundActive() then break end
				if NPCManager.spawn("Warrior") then spawnedCount += 1 end
				task.wait(0.5)
			end
			for _ = 1, waveDef.bosses do
				if not isRoundActive() then break end
				if NPCManager.spawn("Boss") then spawnedCount += 1 end
				task.wait(0.8)
			end
			-- Marked even on early-bail (NPCManager.spawn returning nil at
			-- MAX_NPCS cap, or isRoundActive flipping). The polling loop's
			-- `spawnDone and alive == 0` clear condition stays correct
			-- regardless: stragglers were either spawned (and need killing)
			-- or were skipped (so the wave is genuinely complete once
			-- everything alive is dead).
			spawnDone = true
		end)

		-- Initial broadcast: nothing spawned yet, but pretend all are
		-- pending so the kid sees "5 / 5" from t=0 instead of "0 / 5".
		fireWaveState(waveNum, STATE_ACTIVE, {
			enemiesLeft = totalEnemies,
			totalEnemies = totalEnemies,
			isBossWave = waveDef.isBoss,
		})

		local startTime = tick()
		local timedOut = false
		while isRoundActive() do
			task.wait(WAVE_TICK_RATE)
			local elapsed = tick() - startTime
			local alive = countAliveNPCs()
			-- Pending = NPCs the spawn task hasn't placed yet. Once spawnDone
			-- flips, we drop pending to 0 even if MAX_NPCS rejected some — a
			-- skipped NPC will never come, so it shouldn't count as "left to
			-- kill" once spawning has finished trying.
			local pending = if spawnDone then 0 else math.max(0, totalEnemies - spawnedCount)
			local enemiesLeft = alive + pending
			fireWaveState(waveNum, STATE_ACTIVE, {
				enemiesLeft = enemiesLeft,
				totalEnemies = totalEnemies,
				isBossWave = waveDef.isBoss,
			})
			-- Wave cleared the moment spawning finished AND nothing's alive.
			-- No false-clears during the stagger window because spawnDone
			-- gates this branch.
			if spawnDone and alive == 0 then
				break
			end
			if elapsed >= WAVE_TIMEOUT then
				timedOut = true
				break
			end
		end

		if not isRoundActive() then
			table.insert(results, { waveNum = waveNum, status = "ABORTED", clearTime = nil, isBossWave = waveDef.isBoss })
			NPCManager.clearAll()
			break
		end

		local clearTime = tick() - startTime
		if timedOut then
			print(`[NPCManager] Wave {waveNum} TIMEOUT at {math.floor(clearTime)}s with stragglers`)
			fireWaveState(waveNum, STATE_TIMEOUT, { coinReward = 0, isBossWave = waveDef.isBoss })
			NPCManager.clearAll() -- despawn stragglers so the rest period is calm
			table.insert(results, { waveNum = waveNum, status = "TIMEOUT", clearTime = clearTime, isBossWave = waveDef.isBoss })
		else
			print(`[NPCManager] Wave {waveNum} CLEARED in {math.floor(clearTime)}s`)
			fireWaveState(waveNum, STATE_CLEARED, { coinReward = waveDef.coinReward, clearTime = clearTime, isBossWave = waveDef.isBoss })
			onWaveCleared(waveNum, waveDef.coinReward)
			table.insert(results, { waveNum = waveNum, status = "CLEARED", clearTime = clearTime, isBossWave = waveDef.isBoss })
		end

		-- RESTING: 15s breather. Skipped after wave 3 (round ends right
		-- after the boss wave's CLEARED/TIMEOUT, no rest needed).
		-- Pre-warn the kid about the boss wave during the rest preceding it
		-- — the client switches to a red-themed countdown so the boss
		-- doesn't surprise-spawn after a calm yellow rest pill.
		if waveNum < NUM_WAVES then
			local nextWaveNum = waveNum + 1
			local nextIsBoss = WAVE_DEFS[nextWaveNum].isBoss
			for sec = REST_DURATION, 1, -1 do
				if not isRoundActive() then break end
				fireWaveState(waveNum, STATE_RESTING, {
					secondsLeft = sec,
					nextWave = nextWaveNum,
					nextIsBoss = nextIsBoss,
				})
				task.wait(1)
			end
		end
	end

	-- ===== Sprint 10: Mega-Boss-Round path =====
	-- After the standard NUM_WAVES finish, if the round number is a
	-- multiple of MEGA_BOSS_CADENCE, append a Mega-Boss wave: spawn
	-- BLAZE THE INFERNO LORD via BossManager, wait for the kid(s) to
	-- kill it OR the timeout to despawn it. Death/timeout exit paths
	-- both append a wave result so the round-end summary shows the
	-- boss outcome. Banner + analytics + rewards land in commits 5-6;
	-- this commit just gets the encounter to start and end cleanly.
	--
	-- Note: BossManager.isActive flips to false either when boss HP
	-- hits 0 (commit 4 wires player damage in) or when the timeout
	-- branch below calls despawn(). For commit 3, the kid CAN see the
	-- boss appear but can't damage it yet (no findHitNPC integration);
	-- the encounter exits via timeout. That's fine for incremental
	-- shipping — kid sees the model, knows something's coming.
	if isRoundActive() and roundNumber % MEGA_BOSS_CADENCE == 0 then
		print(`[NPCManager] Round {roundNumber} is a Mega-Boss-Round; spawning Blaze`)
		-- Player-count snapshot at spawn — peer audit explicitly
		-- guards against dynamic mid-fight rescaling. Locked here.
		local activePlayerCount = #Players:GetPlayers()
		local boss = BossManager.spawnBlaze(activePlayerCount)
		if boss then
			local startTime = tick()
			local timedOut = false
			while isRoundActive() and BossManager.isActive() do
				task.wait(0.5)
				if tick() - startTime >= MEGA_BOSS_FIGHT_DURATION then
					timedOut = true
					break
				end
			end
			local clearTime = tick() - startTime
			-- Force despawn if we exited via timeout / round-end with
			-- the boss still alive. The reward path (commit 5) hooks
			-- in earlier (intercepts the death moment) so a CLEARED
			-- exit's despawn happens via the reward path, not here.
			if BossManager.isActive() then
				BossManager.despawn()
			end
			local status: string
			if timedOut then
				status = "TIMEOUT"
				print(`[NPCManager] Blaze TIMED OUT after {math.floor(clearTime)}s`)
			elseif not isRoundActive() then
				status = "ABORTED"
			else
				status = "CLEARED"
				print(`[NPCManager] Blaze CLEARED in {math.floor(clearTime)}s`)
			end
			table.insert(results, {
				waveNum = NUM_WAVES + 1,
				status = status,
				clearTime = if status == "CLEARED" then clearTime else nil,
				isBossWave = true,
			})
		end
	end

	-- Final cleanup: any straggler NPCs (e.g. a Boss whose death animation
	-- is mid-flight when the loop exits) are despawned so the intermission
	-- starts visually clean. Defensive Blaze despawn for the rare case
	-- where we exited the loop with him alive (round force-ended).
	NPCManager.clearAll()
	if BossManager.isActive() then
		BossManager.despawn()
	end
	return results
end

-- Cleanup helper: kill all NPCs (called on round end so they don't bleed
-- into the intermission)
function NPCManager.clearAll()
	for id in npcs do
		NPCManager.despawn(id)
	end
end

-- Public lookup so CombatManager can find an NPC by its model (for hit detection)
function NPCManager.getNPCByModel(model: Model): NPCState?
	for _, state in npcs do
		if state.model == model then
			return state
		end
	end
	return nil
end

return NPCManager
