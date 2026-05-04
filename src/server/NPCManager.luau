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

-- Wave configuration. Each wave defines what to spawn and the delay before
-- the next wave. Indexed by wave number; loops back to the last entry once
-- the round runs out of defined waves (so longer rounds keep getting harder).
local WAVES = {
	{ scouts = 2, warriors = 0, bosses = 0, delayAfter = 30 }, -- wave 1: scouts only
	{ scouts = 3, warriors = 1, bosses = 0, delayAfter = 30 }, -- wave 2: warrior intro
	{ scouts = 4, warriors = 2, bosses = 0, delayAfter = 30 }, -- wave 3: more warriors
	{ scouts = 3, warriors = 3, bosses = 1, delayAfter = 40 }, -- wave 4: first boss
	{ scouts = 5, warriors = 4, bosses = 1, delayAfter = 40 }, -- wave 5+: chaos
}

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

-- Wave system: spawns scaling waves over the round.
-- Driven by the round's active state from RoundManager.
function NPCManager.startWaveLoop(isRoundActive: () -> boolean)
	task.spawn(function()
		while true do
			-- Wait for a round to be active before spawning waves
			while not isRoundActive() do
				task.wait(2)
			end

			local waveNum = 1
			while isRoundActive() do
				-- Index into WAVES; clamp to last entry so long rounds keep peak difficulty
				local wave = WAVES[math.min(waveNum, #WAVES)]
				print(`[NPCManager] Spawning wave {waveNum}: {wave.scouts}S {wave.warriors}W {wave.bosses}B`)

				-- M2 fix: each spawn loop checks isRoundActive so a mid-wave
				-- round-end doesn't burn InsertService calls + immediate cleanup.
				for i = 1, wave.scouts do
					if not isRoundActive() then break end
					NPCManager.spawn("Scout")
					task.wait(0.3)
				end
				for i = 1, wave.warriors do
					if not isRoundActive() then break end
					NPCManager.spawn("Warrior")
					task.wait(0.5)
				end
				for i = 1, wave.bosses do
					if not isRoundActive() then break end
					NPCManager.spawn("Boss")
					task.wait(0.8)
				end

				task.wait(wave.delayAfter)
				waveNum += 1
			end

			-- Round ended: clear all NPCs so the next round starts clean
			for id in npcs do
				NPCManager.despawn(id)
			end
		end
	end)
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
