--!strict
-- Builds the Crystal Lair: peaceful safe-zone hub where players spawn,
-- manage their dragon, practice on dummies, and step through a portal
-- to enter the Arena.
--
-- Spatial layout: the Lair sits at (2000, 500, 0) — far enough from the
-- Arena (centered at origin) that fog hides one from the other. Players
-- teleport between zones via portals (Sprint 5 Part E).
--
-- Visual contents (V1, programmatic placeholders for Meshy hero pieces):
-- - Stone disc floor with rune-glow accents
-- - Central rainbow crystal pillar (placeholder; Sprint 7: swap for Meshy
--   "tall fantasy crystal cluster" mesh)
-- - 4 element arches at cardinal points (Fire/Ice/Lightning/Earth crystals)
-- - 3 practice dummies (simple targets that take damage but auto-heal)
-- - Stat Stone obelisk (interaction hook for Sprint 7 stat upgrade UI)
-- - Shop Stone obelisk (interaction hook for Sprint 9 monetization UI)
-- - Portal-to-Arena disc (Sprint 5 Part E adds the Touched teleport handler)

local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")

-- Hero asset: crystal tower (Meshy AI generated) for the central pillar.
-- Falls back to programmatic stacked-cubes if the asset fails to load.
local CRYSTAL_TOWER_ASSET = 72162270981514
local OBELISK_ASSET = 90068928485508 -- replaces Stat Stone + Shop Stone placeholders

-- Same load-and-place helper pattern as ArenaBuilder. Inlined here rather
-- than shared because two duplications is acceptable; refactor to a
-- shared MeshLoader module if a third caller appears.
local function loadHeroPiece(assetId: number, targetCFrame: CFrame, scale: number?): Model?
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not result then
		warn(`[LairBuilder] Failed to load hero asset {assetId}: {result}`)
		return nil
	end
	local container = result :: Model
	local model: Model = container
	for _, child in container:GetChildren() do
		if child:IsA("Model") then
			model = child :: Model
			break
		end
	end
	local cloned = model:Clone()
	container:Destroy()
	if scale then
		cloned:ScaleTo(scale)
	end
	cloned:PivotTo(targetCFrame)
	for _, descendant in cloned:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			-- Lair pieces stay non-collidable — they're decorative and we
			-- don't want kids snagging on the central pillar while orbiting
			-- it for the upgrade station. Differs from Arena towers, which
			-- ARE collidable so they work as cover.
			descendant.CanCollide = false
		end
	end
	return cloned
end

local LairBuilder = {}

-- World-space constants. The Y=500 keeps the Lair high in the sky so it
-- visually reads as "above the chaos" — players literally look down at
-- the Arena clouds when they exit.
local LAIR_CENTER = Vector3.new(2000, 500, 0)
local FLOOR_RADIUS = 100
local FLOOR_THICKNESS = 6
local PORTAL_DISTANCE_FROM_CENTER = 70 -- portal sits at south edge of disc
local LAIR_TAG = "DragonWarz_Lair"
-- Sprint 7: tags so the client (ProximityPrompt) and combat (dummy hit
-- detection carve-out) can find these instances without hard-coding paths.
local STAT_STONE_TAG = "DragonWarz_StatStone"
local SHOP_STONE_TAG = "DragonWarz_ShopStone"
local PRACTICE_DUMMY_TAG = "DragonWarz_PracticeDummy"

-- Sprint 7: per-dummy HP state. Index = dummy id; entry = { part, maxHp,
-- currentHp, alive }. Damage path mutates currentHp; when it hits 0, the
-- dummy goes invisible + non-targetable for 3 seconds then "respawns".
-- Module-level so the fireBreath carve-out (separate commit) can call
-- damageDummy without LairBuilder needing to share state via globals.
local DUMMY_MAX_HP = 100
local DUMMY_RESPAWN_SEC = 3
type DummyState = {
	id: number,
	part: BasePart,
	billboard: BillboardGui,
	hpLabel: TextLabel,
	maxHp: number,
	currentHp: number,
	alive: boolean,
}
local dummies: { DummyState } = {}

LairBuilder.LAIR_CENTER = LAIR_CENTER
LairBuilder.FLOOR_RADIUS = FLOOR_RADIUS

-- Spawn points: ring of 6 positions around the central pillar at radius 30.
-- Players land here on join + after death + after returning from Arena.
local SPAWN_RING_RADIUS = 30
local SPAWN_HEIGHT_OFFSET = 8 -- above floor surface
local spawnPoints: { Vector3 } = {}
for i = 1, 6 do
	local angle = (i - 1) * math.pi * 2 / 6
	table.insert(spawnPoints, LAIR_CENTER + Vector3.new(
		math.cos(angle) * SPAWN_RING_RADIUS,
		FLOOR_THICKNESS / 2 + SPAWN_HEIGHT_OFFSET,
		math.sin(angle) * SPAWN_RING_RADIUS
	))
end

LairBuilder.spawnPoints = spawnPoints

function LairBuilder.getRandomSpawnPoint(): Vector3
	return spawnPoints[math.random(1, #spawnPoints)]
end

-- Helper: anchored, non-collidable Part with sensible defaults
local function makePart(name: string, parent: Instance, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	CollectionService:AddTag(p, LAIR_TAG)
	p.Parent = parent
	return p
end

-- Build the stone disc floor + underbase. The disc alone reads as "stuff
-- hanging in space" so we layer a thicker rock chunk below + a tapered
-- bottom + ambient clouds floating around. Now reads as a substantial
-- piece of floating sky island instead of a magic carpet.
local function buildFloor(parent: Instance)
	-- Surface disc — what players actually walk on
	local floor = makePart("LairFloor", parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(FLOOR_THICKNESS, FLOOR_RADIUS * 2, FLOOR_RADIUS * 2),
		CFrame = CFrame.new(LAIR_CENTER) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(80, 70, 90), -- weathered stone
		Material = Enum.Material.Slate,
		CanCollide = true, -- floor IS collidable
	})

	-- Underbase: thick rock body below the disc. Large block of darker
	-- stone, gives the "this is a chunk of floating island, not just a
	-- platform" silhouette. Decorative-only, non-collidable so it doesn't
	-- block the portal teleport landing zone underneath.
	makePart("LairUnderbase", parent, {
		Size = Vector3.new(FLOOR_RADIUS * 1.9, 70, FLOOR_RADIUS * 1.9),
		CFrame = CFrame.new(LAIR_CENTER + Vector3.new(0, -38, 0)),
		Color = Color3.fromRGB(55, 50, 65),
		Material = Enum.Material.Rock,
	})

	-- Tapered bottom: smaller block under the underbase. Together they
	-- read as "island chunk narrowing to a point" — classic floating-isle
	-- silhouette from sky-fantasy art.
	makePart("LairTaperedBase", parent, {
		Size = Vector3.new(FLOOR_RADIUS * 1.0, 50, FLOOR_RADIUS * 1.0),
		CFrame = CFrame.new(LAIR_CENTER + Vector3.new(0, -100, 0)),
		Color = Color3.fromRGB(40, 35, 50),
		Material = Enum.Material.Rock,
	})

	-- Pointed bottom tip — a flat-bottomed cone-ish chunk for the silhouette
	makePart("LairBottomTip", parent, {
		Size = Vector3.new(FLOOR_RADIUS * 0.4, 40, FLOOR_RADIUS * 0.4),
		CFrame = CFrame.new(LAIR_CENTER + Vector3.new(0, -145, 0)),
		Color = Color3.fromRGB(30, 25, 40),
		Material = Enum.Material.Rock,
	})

	-- Ambient clouds floating around the Lair. Soft glass spheres at varied
	-- distances + heights — give visual context so the Lair isn't surrounded
	-- by empty void. 12 clouds at scattered positions.
	for i = 1, 12 do
		local angle = (i - 1) * math.pi * 2 / 12 + math.random() * 0.3
		local distance = 130 + math.random(0, 60)
		local height = math.random(-60, 40)
		makePart(`AmbientCloud_{i}`, parent, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(
				35 + math.random(0, 25),
				20 + math.random(0, 12),
				35 + math.random(0, 25)
			),
			CFrame = CFrame.new(LAIR_CENTER + Vector3.new(
				math.cos(angle) * distance,
				height,
				math.sin(angle) * distance
			)),
			Color = Color3.fromRGB(255, 255, 255),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.45,
		})
	end

	-- Subtle inner glow ring at floor surface for atmosphere
	local glowRing = makePart("FloorGlowRing", parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, FLOOR_RADIUS * 1.4, FLOOR_RADIUS * 1.4),
		CFrame = CFrame.new(LAIR_CENTER + Vector3.new(0, FLOOR_THICKNESS / 2 + 0.2, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 180, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.6,
	})
end

-- Sprint 8: element-color cycle for the central pillar's glow. Loop
-- through the same six element colors that drive the arches around the
-- Lair so the centerpiece reads as a "convergence point" of all elements.
-- Each step takes ELEMENT_CYCLE_SEC seconds to fade into the next; the
-- whole 6-color cycle runs in 6 × ELEMENT_CYCLE_SEC ≈ 18 seconds, so it
-- feels like a slow magical pulse, not a disco strobe.
local ELEMENT_CYCLE_COLORS = {
	Color3.fromRGB(255, 80, 20),   -- Fire
	Color3.fromRGB(100, 180, 255), -- Ice
	Color3.fromRGB(255, 255, 50),  -- Lightning
	Color3.fromRGB(139, 119, 80),  -- Earth
	Color3.fromRGB(120, 50, 180),  -- Dark
	Color3.fromRGB(255, 230, 180), -- Light
}
local ELEMENT_CYCLE_SEC = 3 -- per-color dwell time

-- Sprint 8: helper that animates a Color3 property in a continuous loop
-- through ELEMENT_CYCLE_COLORS. Used by the central pillar light + the
-- pillar-of-light beam so they cycle in lockstep. instance can be a
-- PointLight (animates .Color) or a BasePart (animates .Color).
local function startColorCycleLoop(instance: Instance, propertyName: string)
	local TweenService = game:GetService("TweenService")
	task.spawn(function()
		local i = 1
		while instance.Parent do
			local target = ELEMENT_CYCLE_COLORS[i]
			local tween = TweenService:Create(instance,
				TweenInfo.new(ELEMENT_CYCLE_SEC, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ [propertyName] = target }
			)
			tween:Play()
			tween.Completed:Wait()
			i = (i % #ELEMENT_CYCLE_COLORS) + 1
		end
	end)
end

-- Central Pillar: try Meshy AI crystal tower first; fall back to a
-- programmatic stacked-cube cluster if asset load fails. Either way the
-- centerpiece reads as the magical focal point of the Lair.
--
-- Sprint 8 glow-up: continuous Y-rotation tween, color-cycling PointLight
-- (Fire→Ice→Lightning→Earth→Dark→Light loop), vertical pillar-of-light
-- beam shooting up to ~Y=600, particle aura at the base. Pulls the eye
-- across the entire Lair to this focal point.
local function buildCentralPillar(parent: Instance)
	local pillarBase = LAIR_CENTER + Vector3.new(0, FLOOR_THICKNESS / 2, 0)
	local TweenService = game:GetService("TweenService")

	-- Hero load attempt. Scale 1.5 — Meshy assets default sizes vary, tune
	-- after seeing the result in playtest.
	local hero = loadHeroPiece(CRYSTAL_TOWER_ASSET, CFrame.new(pillarBase), 1.5)
	if hero then
		hero.Name = "CentralCrystalTower"
		hero.Parent = parent
		-- Add a glow light at the pillar's apex regardless — pulls eye to
		-- the centerpiece. Position relative to bounding box top.
		local _meshCF, meshSize = hero:GetBoundingBox()
		local light = Instance.new("PointLight")
		light.Color = ELEMENT_CYCLE_COLORS[1]
		light.Brightness = 6
		light.Range = 100
		-- Parent light to a part inside the hero — find the first BasePart
		local hostPart: BasePart? = nil
		for _, descendant in hero:GetDescendants() do
			if descendant:IsA("BasePart") then
				hostPart = descendant :: BasePart
				break
			end
		end
		if hostPart then
			light.Parent = hostPart
		end
		-- Element-color cycle on the apex light. Server-side tween,
		-- replicates the .Color change to all clients automatically.
		startColorCycleLoop(light, "Color")

		-- Pillar of light: a thin vertical neon cylinder shooting up
		-- from the tower into the sky. Color-cycles in lockstep with
		-- the apex light so the whole structure pulses as one.
		local PILLAR_HEIGHT = 100
		local pillarBeam = makePart("CentralPillarBeam", parent, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(PILLAR_HEIGHT, 1.5, 1.5),
			CFrame = CFrame.new(pillarBase + Vector3.new(0, PILLAR_HEIGHT / 2 + 30, 0))
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = ELEMENT_CYCLE_COLORS[1],
			Material = Enum.Material.Neon,
			Transparency = 0.5,
		})
		startColorCycleLoop(pillarBeam, "Color")

		-- Continuous slow rotation of the hero. Uses CFrame tween on each
		-- BasePart inside the hero — the asset is welded together so
		-- rotating the first part rotates the whole tower visually.
		-- 12-second revolution is slow enough to feel ambient, not dizzy.
		if hostPart then
			task.spawn(function()
				while hostPart and hostPart.Parent do
					-- Rebuild the goal CFrame each iteration so we always
					-- rotate by exactly 360° from the current orientation,
					-- avoiding cumulative drift if the host moves.
					local startCF = hostPart.CFrame
					for step = 1, 12 do
						if not hostPart.Parent then break end
						local target = startCF * CFrame.Angles(0, math.rad(30 * step), 0)
						local tween = TweenService:Create(hostPart,
							TweenInfo.new(1.0, Enum.EasingStyle.Linear),
							{ CFrame = target }
						)
						tween:Play()
						tween.Completed:Wait()
					end
				end
			end)
		end

		-- Particle aura at the base of the tower. Rising sparkles in
		-- the active element color so the pillar looks alive even from
		-- far away.
		local baseAttach = Instance.new("Attachment")
		baseAttach.Name = "PillarBaseAttach"
		baseAttach.Position = Vector3.new(0, 2, 0)
		baseAttach.Parent = if hostPart then hostPart else (parent:FindFirstChild("LairFloor") :: BasePart)
		local aura = Instance.new("ParticleEmitter")
		aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		aura.Color = ColorSequence.new(ELEMENT_CYCLE_COLORS[1])
		aura.Size = NumberSequence.new(1.5, 0.2)
		aura.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		aura.Lifetime = NumberRange.new(1.5, 3)
		aura.Rate = 30
		aura.Speed = NumberRange.new(3, 6)
		aura.SpreadAngle = Vector2.new(8, 8)
		aura.VelocityInheritance = 0
		aura.Acceleration = Vector3.new(0, 5, 0) -- gentle upward drift
		aura.Parent = baseAttach
		-- Color-cycle the aura particles too via a separate task that
		-- updates aura.Color. ParticleEmitter doesn't accept tween on
		-- ColorSequence, so write directly to it on each cycle step.
		task.spawn(function()
			local i = 1
			while aura.Parent do
				task.wait(ELEMENT_CYCLE_SEC)
				i = (i % #ELEMENT_CYCLE_COLORS) + 1
				aura.Color = ColorSequence.new(ELEMENT_CYCLE_COLORS[i])
			end
		end)
		return
	end

	-- Fallback: 3 stacked colored cubes if the Meshy asset failed
	local heights = { 6, 12, 24 }
	local sizes = { 14, 10, 6 }
	local colors = {
		Color3.fromRGB(100, 80, 200),
		Color3.fromRGB(180, 140, 255),
		Color3.fromRGB(240, 220, 255),
	}
	local cumulativeHeight = FLOOR_THICKNESS / 2
	for i = 1, 3 do
		cumulativeHeight += heights[i] / 2
		makePart(`CrystalLayer_{i}`, parent, {
			Shape = Enum.PartType.Block,
			Size = Vector3.new(sizes[i], heights[i], sizes[i]),
			CFrame = CFrame.new(LAIR_CENTER + Vector3.new(0, cumulativeHeight, 0))
				* CFrame.Angles(0, math.rad((i - 1) * 30), 0),
			Color = colors[i],
			Material = Enum.Material.Neon,
			Transparency = 0.15,
		})
		cumulativeHeight += heights[i] / 2
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(200, 180, 255)
	light.Brightness = 4
	light.Range = 60
	light.Parent = parent:FindFirstChild("CrystalLayer_3")
end

-- Element arches at compass points. Each is a stone post + horizontal beam +
-- crystal accent in its element's color. Six arches total (one per element)
-- at 60° apart around the lair.
local function buildElementArches(parent: Instance)
	local elements = {
		{ name = "Fire", color = Color3.fromRGB(255, 80, 20) },
		{ name = "Ice", color = Color3.fromRGB(100, 180, 255) },
		{ name = "Lightning", color = Color3.fromRGB(255, 255, 50) },
		{ name = "Earth", color = Color3.fromRGB(139, 119, 80) },
		{ name = "Dark", color = Color3.fromRGB(60, 20, 80) },
		{ name = "Light", color = Color3.fromRGB(255, 230, 180) },
	}
	local archRadius = 75
	local archHeight = 22
	local postWidth = 2

	for i, element in elements do
		local angle = (i - 1) * math.pi * 2 / 6
		local archCenter = LAIR_CENTER + Vector3.new(
			math.cos(angle) * archRadius,
			FLOOR_THICKNESS / 2 + archHeight / 2,
			math.sin(angle) * archRadius
		)
		-- Two vertical posts (left + right of arch)
		for side = -1, 1, 2 do
			local lateral = Vector3.new(-math.sin(angle), 0, math.cos(angle)) * 5 * side
			makePart(`Arch_{element.name}_Post`, parent, {
				Size = Vector3.new(postWidth, archHeight, postWidth),
				CFrame = CFrame.new(archCenter + lateral),
				Color = Color3.fromRGB(60, 55, 70),
				Material = Enum.Material.Slate,
			})
		end
		-- Horizontal top beam
		makePart(`Arch_{element.name}_Beam`, parent, {
			Size = Vector3.new(12, postWidth, postWidth),
			CFrame = CFrame.new(archCenter + Vector3.new(0, archHeight / 2 + postWidth / 2, 0))
				* CFrame.Angles(0, -angle - math.pi / 2, 0),
			Color = Color3.fromRGB(60, 55, 70),
			Material = Enum.Material.Slate,
		})
		-- Glowing element crystal hung from the center of the beam
		local crystal = makePart(`Arch_{element.name}_Crystal`, parent, {
			Shape = Enum.PartType.Block,
			Size = Vector3.new(2, 3, 2),
			CFrame = CFrame.new(archCenter + Vector3.new(0, archHeight / 2 - 2, 0))
				* CFrame.Angles(math.rad(45), math.rad((i - 1) * 60), math.rad(45)),
			Color = element.color,
			Material = Enum.Material.Neon,
			Transparency = 0.1,
		})

		-- Sprint 8: pulsing PointLight inside the crystal so each arch
		-- visibly breathes its element color. Brightness tweens 2 → 6 →
		-- 2 on a ~3 second cycle. Each arch starts on a different phase
		-- (offset by i * 0.5s) so the six arches don't pulse in lockstep
		-- — feels like an organic chorus rather than a digital flicker.
		local archLight = Instance.new("PointLight")
		archLight.Name = "ArchLight"
		archLight.Color = element.color
		archLight.Brightness = 3
		archLight.Range = 18
		archLight.Parent = crystal
		local TweenService = game:GetService("TweenService")
		task.delay((i - 1) * 0.5, function()
			while archLight.Parent do
				local up = TweenService:Create(archLight,
					TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Brightness = 7 }
				)
				up:Play()
				up.Completed:Wait()
				if not archLight.Parent then break end
				local down = TweenService:Create(archLight,
					TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Brightness = 2 }
				)
				down:Play()
				down.Completed:Wait()
			end
		end)

		-- Ground glow circle under each arch — a thin neon disc on the
		-- floor in the element's color. Reads as "this is a themed area"
		-- and gives the kid a target to step onto for the walk-through
		-- particle burst below.
		local groundGlow = makePart(`Arch_{element.name}_GroundGlow`, parent, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 16, 16),
			CFrame = CFrame.new(LAIR_CENTER + Vector3.new(
				math.cos(angle) * archRadius,
				FLOOR_THICKNESS / 2 + 0.3,
				math.sin(angle) * archRadius
			)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = element.color,
			Material = Enum.Material.Neon,
			Transparency = 0.55,
		})

		-- Walk-through particle burst: when a player walks within ~6 studs
		-- of the arch's center on the ground glow disc, fire an element-
		-- themed particle burst from an Attachment on the disc. Server-
		-- side proximity check at low frequency (every 0.4s); each burst
		-- has a 2-second cooldown per player so a kid loitering on the
		-- disc doesn't spawn endless particles.
		local burstAttach = Instance.new("Attachment")
		burstAttach.Name = "BurstAttach"
		burstAttach.Position = Vector3.new(0, 0, 1) -- sits on the disc surface
		burstAttach.Parent = groundGlow
		local burst = Instance.new("ParticleEmitter")
		burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		burst.Color = ColorSequence.new(element.color)
		burst.Size = NumberSequence.new(2, 0.3)
		burst.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		burst.Lifetime = NumberRange.new(0.8, 1.4)
		burst.Rate = 0 -- emitted in pulses by :Emit() below, not continuously
		burst.Speed = NumberRange.new(8, 16)
		burst.SpreadAngle = Vector2.new(80, 80)
		burst.Acceleration = Vector3.new(0, -3, 0) -- slight gravity arc
		burst.Parent = burstAttach

		-- Track per-player cooldown via a closure so kids don't trigger
		-- the burst on every poll cycle.
		local lastBurstTime: { [number]: number } = {}
		local archCenterXZ = Vector3.new(
			LAIR_CENTER.X + math.cos(angle) * archRadius,
			0,
			LAIR_CENTER.Z + math.sin(angle) * archRadius
		)
		local TRIGGER_RADIUS_SQ = 6 * 6
		local BURST_COOLDOWN = 2
		task.spawn(function()
			while groundGlow.Parent do
				task.wait(0.4)
				local now = tick()
				for _, plr in game:GetService("Players"):GetPlayers() do
					local char = plr.Character
					if char and char.PrimaryPart then
						local pos = char.PrimaryPart.Position
						-- 2D distance check (ignore Y so kids flying above
						-- don't trigger the burst — they have to be near
						-- the floor).
						local dx = pos.X - archCenterXZ.X
						local dz = pos.Z - archCenterXZ.Z
						local distSq = dx * dx + dz * dz
						local heightDelta = math.abs(pos.Y - (LAIR_CENTER.Y + FLOOR_THICKNESS / 2))
						if distSq < TRIGGER_RADIUS_SQ and heightDelta < 12 then
							local last = lastBurstTime[plr.UserId] or 0
							if now - last > BURST_COOLDOWN then
								lastBurstTime[plr.UserId] = now
								burst:Emit(20)
							end
						end
					end
				end
			end
		end)
	end
end

-- Practice dummies: 3 simple humanoid-shaped targets. Sprint 7 makes them
-- functional — each takes damage from a Lair-shooter's breath, shows a
-- floating "-N" + HP bar, and "respawns" after a 3-second KO. The
-- fireBreath carve-out that routes Lair-shooter cones into damageDummy
-- ships in a SEPARATE commit (peer audit guidance — that's the only Sprint
-- 7 change touching the safe-zone gate so it gets blast-radius isolation).
local function buildPracticeDummies(parent: Instance)
	for i = 1, 3 do
		local angle = math.rad(60 + i * 50) -- arc on one side of the lair
		local pos = LAIR_CENTER + Vector3.new(
			math.cos(angle) * 50,
			FLOOR_THICKNESS / 2 + 5,
			math.sin(angle) * 50
		)
		-- Body. Tagged + collectible so server-side cone hit detection (in
		-- the fireBreath carve-out) can identify a hit on a dummy. The body
		-- is the canonical "target part" for the cone test — ignore the head
		-- so we only count one hit per breath even if both parts are in cone.
		local body = makePart(`Dummy_{i}_Body`, parent, {
			Size = Vector3.new(4, 5, 4),
			CFrame = CFrame.new(pos),
			Color = Color3.fromRGB(150, 100, 80),
			Material = Enum.Material.Wood,
		})
		CollectionService:AddTag(body, PRACTICE_DUMMY_TAG)
		-- Head — visual only, NOT tagged (only the body is the cone target)
		makePart(`Dummy_{i}_Head`, parent, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3, 3, 3),
			CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)),
			Color = Color3.fromRGB(200, 150, 120),
			Material = Enum.Material.Wood,
		})

		-- Stacked "PRACTICE" + HP-bar billboard. The HP label updates on hit
		-- and resets on respawn so the kid sees their upgrade impact.
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(140, 50)
		billboard.StudsOffset = Vector3.new(0, 5, 0)
		billboard.Adornee = body
		billboard.Parent = parent
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0.55, 0)
		label.BackgroundTransparency = 1
		label.Text = "PRACTICE"
		label.TextColor3 = Color3.fromRGB(220, 220, 220)
		label.TextStrokeTransparency = 0
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = billboard
		local hpLabel = Instance.new("TextLabel")
		hpLabel.Name = "HpLabel"
		hpLabel.Size = UDim2.new(1, 0, 0.45, 0)
		hpLabel.Position = UDim2.fromScale(0, 0.55)
		hpLabel.BackgroundTransparency = 1
		hpLabel.Text = `{DUMMY_MAX_HP} / {DUMMY_MAX_HP} HP`
		hpLabel.TextColor3 = Color3.fromRGB(150, 220, 150)
		hpLabel.TextStrokeTransparency = 0
		hpLabel.Font = Enum.Font.Gotham
		hpLabel.TextScaled = true
		hpLabel.Parent = billboard

		table.insert(dummies, {
			id = i,
			part = body,
			billboard = billboard,
			hpLabel = hpLabel,
			maxHp = DUMMY_MAX_HP,
			currentHp = DUMMY_MAX_HP,
			alive = true,
		})
	end
end

-- Sprint 7: cone hit detection against practice dummies. Mirrors the
-- CombatManager.findHitPlayer/findHitNPC pattern so the carve-out commit
-- can plug this in symmetrically. Returns the closest dummy in the cone
-- or nil. Range matches breath range (100 studs); the dummy positions
-- are within ~50 studs of the Lair center so this is generous.
local DUMMY_BREATH_RANGE = 100
function LairBuilder.findHitDummy(origin: Vector3, direction: Vector3): DummyState?
	if direction.Magnitude < 0.001 then return nil end
	local dirUnit = direction.Unit
	local closest: DummyState? = nil
	local closestDist = DUMMY_BREATH_RANGE
	for _, dummy in dummies do
		if dummy.alive then
			local toTarget = dummy.part.Position - origin
			local dist = toTarget.Magnitude
			if dist < closestDist then
				local dot = toTarget.Unit:Dot(dirUnit)
				if dot > 0.85 then -- match findHitPlayer's ~30 degree cone
					closestDist = dist
					closest = dummy
				end
			end
		end
	end
	return closest
end

-- Sprint 7: apply damage to a dummy. Returns the post-hit HP so the
-- carve-out can fire the DummyHit remote with the right number for the
-- floating damage label. KO at HP <= 0 → 3-second invisible respawn.
function LairBuilder.damageDummy(dummy: DummyState, amount: number): number
	if not dummy.alive then return 0 end
	dummy.currentHp = math.max(0, dummy.currentHp - amount)
	dummy.hpLabel.Text = `{dummy.currentHp} / {dummy.maxHp} HP`

	-- Color-tint HP label: green (full) → yellow (half) → red (low) so the
	-- kid sees how close to KO at a glance.
	local hpFrac = dummy.currentHp / dummy.maxHp
	if hpFrac > 0.6 then
		dummy.hpLabel.TextColor3 = Color3.fromRGB(150, 220, 150)
	elseif hpFrac > 0.3 then
		dummy.hpLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	else
		dummy.hpLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
	end

	if dummy.currentHp <= 0 then
		-- KO: hide body + billboard, respawn after DUMMY_RESPAWN_SEC. The
		-- alive flag gates findHitDummy so a downed dummy can't be hit.
		dummy.alive = false
		dummy.part.Transparency = 1
		dummy.billboard.Enabled = false
		task.delay(DUMMY_RESPAWN_SEC, function()
			-- Same dummy table — ResetOnSpawn doesn't apply to non-Player parts.
			dummy.currentHp = dummy.maxHp
			dummy.alive = true
			dummy.part.Transparency = 0
			dummy.billboard.Enabled = true
			dummy.hpLabel.Text = `{dummy.maxHp} / {dummy.maxHp} HP`
			dummy.hpLabel.TextColor3 = Color3.fromRGB(150, 220, 150)
		end)
	end
	return dummy.currentHp
end

-- Stat Stone obelisk + Shop Stone obelisk. Tries to load the Roblox
-- obelisk asset; falls back to programmatic stone Parts if load fails.
-- Sprint 7/9 add the ProximityPrompt or Touched handlers that open the
-- upgrade/shop UI; this part is just the visual.
local function buildInteractionStones(parent: Instance)
	-- Stat Stone (left of pillar)
	local statPos = LAIR_CENTER + Vector3.new(-50, FLOOR_THICKNESS / 2, 0)
	local statHero = loadHeroPiece(OBELISK_ASSET, CFrame.new(statPos), 1)
	local statStone: BasePart
	if statHero then
		statHero.Name = "StatStoneHero"
		statHero.Parent = parent
		-- Pick a BasePart inside the hero to adornee the BillboardGui to;
		-- runes overlay stays in its prior CFrame so it floats in front
		-- of the hero (looks like a magical glyph hovering over the stone).
		local anchor: BasePart? = nil
		for _, descendant in statHero:GetDescendants() do
			if descendant:IsA("BasePart") then
				anchor = descendant :: BasePart
				break
			end
		end
		statStone = anchor or makePart("StatStoneAnchor", parent, {
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(statPos + Vector3.new(0, 7, 0)),
			Transparency = 1,
		})
	else
		statStone = makePart("StatStone", parent, {
			Size = Vector3.new(4, 14, 4),
			CFrame = CFrame.new(statPos + Vector3.new(0, 7, 0)),
			Color = Color3.fromRGB(50, 70, 110),
			Material = Enum.Material.Slate,
		})
	end
	local statRunes = makePart("StatStoneRunes", parent, {
		Size = Vector3.new(4.1, 8, 0.2),
		CFrame = statStone.CFrame * CFrame.new(0, 0, 2.05),
		Color = Color3.fromRGB(100, 200, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.3,
	})
	local statLabel = Instance.new("BillboardGui")
	statLabel.Size = UDim2.fromOffset(140, 40)
	statLabel.StudsOffset = Vector3.new(0, 9, 0)
	statLabel.Adornee = statStone
	statLabel.Parent = parent
	local sl = Instance.new("TextLabel")
	sl.Size = UDim2.fromScale(1, 1)
	sl.BackgroundTransparency = 1
	sl.Text = "UPGRADE"
	sl.TextColor3 = Color3.fromRGB(120, 220, 255)
	sl.TextStrokeTransparency = 0
	sl.Font = Enum.Font.GothamBlack
	sl.TextScaled = true
	sl.Parent = statLabel

	-- Sprint 7: tag + ProximityPrompt. POST-PLAYTEST FIX: parenting the
	-- prompt to `statStone` was unreliable. When the hero asset loads,
	-- `statStone` is whatever the first BasePart descendant happens to
	-- be — could be a tiny detail piece embedded deep in the obelisk
	-- mesh with a Position offset that doesn't match the obelisk's
	-- visible center. Plus RequiresLineOfSight=true could be blocked by
	-- the obelisk's own body geometry, so the kid walking up to the
	-- visible obelisk would never see the prompt fire.
	--
	-- Fix: create a dedicated invisible 8x14x8 interaction anchor at the
	-- KNOWN obelisk position, parent the prompt to it, tag it. The anchor
	-- is reliably positioned, large enough that ProximityPrompt's range
	-- check works from any angle, and decoupled from the hero asset's
	-- internal structure. RequiresLineOfSight = false because the anchor
	-- is invisible and we don't want the visible obelisk to occlude it.
	-- Range 8 (slightly larger than 6) compensates for the anchor size.
	local interactionAnchor = makePart("StatStoneInteraction", parent, {
		Size = Vector3.new(12, 18, 12),
		CFrame = CFrame.new(statPos + Vector3.new(0, 7, 0)),
		Transparency = 1,
		CanCollide = false, -- kid can walk through (and they need to to read the prompt)
	})
	CollectionService:AddTag(interactionAnchor, STAT_STONE_TAG)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StatStonePrompt"
	prompt.ActionText = "Upgrade Dragon"
	prompt.ObjectText = "Stat Stone"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	-- Range 14 (was 8). Playtest feedback was kids would walk past the
	-- obelisk without the prompt firing reliably. 14 studs is a 2-3 step
	-- cushion around the visible obelisk so casual approach always
	-- triggers the prompt without it going off when crossing the Lair
	-- on the way to the portal.
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = interactionAnchor

	-- ===== EYE CANDY =====
	-- Sprint 7 polish: kid playtest reported the obelisk reads "lame".
	-- Layer a floating mini-crystal above it with continuous rotation,
	-- bobbing motion, particle sparkles, and a colored point light. Reads
	-- as a magical interaction point — pulls the eye to it from across
	-- the Lair so kids notice WHERE to upgrade without needing a marker.
	local crystalCenter = statPos + Vector3.new(0, 18, 0) -- ~4 studs above obelisk top
	local crystal = makePart("StatStoneCrystal", parent, {
		Size = Vector3.new(2.5, 4, 2.5),
		CFrame = CFrame.new(crystalCenter) * CFrame.Angles(0, 0, math.rad(45)),
		Color = Color3.fromRGB(120, 220, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.15,
	})
	-- Continuous rotation via TweenService loop. RepeatCount = -1 keeps
	-- it spinning forever; reverses=false so it doesn't ping-pong.
	-- Server-side tween, replicates to clients automatically (Anchored
	-- parts replicate CFrame changes at low cost).
	local TweenService = game:GetService("TweenService")
	local rotationGoal = crystal.CFrame * CFrame.Angles(0, math.rad(360), 0)
	local rotationTween = TweenService:Create(crystal,
		TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, 0),
		{ CFrame = rotationGoal }
	)
	rotationTween:Play()

	-- Sparkle particles emitted from the crystal so it visibly "magic"s
	-- without a custom mesh.
	local crystalAttach = Instance.new("Attachment")
	crystalAttach.Parent = crystal
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(Color3.fromRGB(180, 240, 255))
	sparkles.Size = NumberSequence.new(0.6, 0.1)
	sparkles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkles.Lifetime = NumberRange.new(0.8, 1.6)
	sparkles.Rate = 25
	sparkles.Speed = NumberRange.new(0.5, 2)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = crystalAttach

	-- Colored point light cast onto the obelisk + floor below. Range tuned
	-- so the floor disc immediately around the obelisk picks up a cyan
	-- glow — visible from far away, draws the kid's eye toward this
	-- specific obelisk (vs. the Shop Stone which has no such glow).
	local crystalLight = Instance.new("PointLight")
	crystalLight.Color = Color3.fromRGB(120, 220, 255)
	crystalLight.Brightness = 4
	crystalLight.Range = 30
	crystalLight.Parent = crystal

	-- Smaller orbital crystals that circle the main one. Adds depth +
	-- "this is special" feeling. Three orbiters at 120° spacing.
	for i = 1, 3 do
		local orbitCrystal = makePart(`StatStoneOrbiter_{i}`, parent, {
			Size = Vector3.new(1, 1.5, 1),
			Color = Color3.fromRGB(150, 230, 255),
			Material = Enum.Material.Neon,
			Transparency = 0.2,
		})
		-- Orbit via TweenService too. Each orbiter starts at a different
		-- angle around the crystal so they're spread evenly. Tweening the
		-- CFrame around a vertical axis through crystalCenter.
		local startAngle = (i - 1) * math.pi * 2 / 3
		local radius = 4
		orbitCrystal.CFrame = CFrame.new(crystalCenter + Vector3.new(
			math.cos(startAngle) * radius, 0, math.sin(startAngle) * radius
		))
		-- Multi-step orbit: tween through 4 quarter-points so the path is
		-- circular, not just two endpoints. Each orbiter takes 8 seconds
		-- per revolution.
		task.spawn(function()
			while orbitCrystal.Parent do
				for step = 1, 8 do
					local angle = startAngle + math.pi * 2 * (step / 8)
					local target = CFrame.new(crystalCenter + Vector3.new(
						math.cos(angle) * radius, math.sin(angle * 2) * 0.5, math.sin(angle) * radius
					))
					local stepTween = TweenService:Create(orbitCrystal,
						TweenInfo.new(1.0, Enum.EasingStyle.Linear),
						{ CFrame = target }
					)
					stepTween:Play()
					stepTween.Completed:Wait()
				end
			end
		end)
	end

	-- Shop Stone (right of pillar) — same obelisk asset, mirror position
	local shopPos = LAIR_CENTER + Vector3.new(50, FLOOR_THICKNESS / 2, 0)
	local shopHero = loadHeroPiece(OBELISK_ASSET, CFrame.new(shopPos), 1)
	local shopStone: BasePart
	if shopHero then
		shopHero.Name = "ShopStoneHero"
		shopHero.Parent = parent
		local anchor: BasePart? = nil
		for _, descendant in shopHero:GetDescendants() do
			if descendant:IsA("BasePart") then
				anchor = descendant :: BasePart
				break
			end
		end
		shopStone = anchor or makePart("ShopStoneAnchor", parent, {
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(shopPos + Vector3.new(0, 7, 0)),
			Transparency = 1,
		})
	else
		shopStone = makePart("ShopStone", parent, {
			Size = Vector3.new(4, 14, 4),
			CFrame = CFrame.new(shopPos + Vector3.new(0, 7, 0)),
			Color = Color3.fromRGB(110, 80, 40),
			Material = Enum.Material.Slate,
		})
	end
	local shopRunes = makePart("ShopStoneRunes", parent, {
		Size = Vector3.new(4.1, 8, 0.2),
		CFrame = shopStone.CFrame * CFrame.new(0, 0, 2.05),
		Color = Color3.fromRGB(255, 215, 80),
		Material = Enum.Material.Neon,
		Transparency = 0.3,
	})
	-- Sprint 7: tag the shop stone (mostly so future Sprint 9 work can find
	-- it via CollectionService too) and add a "🔒 Coming Soon" sub-label so
	-- a kid who walks up + presses E doesn't bounce off thinking the
	-- obelisk is broken. The Stat Stone has the upgrade prompt; the Shop
	-- Stone is intentionally signposted as a future feature.
	CollectionService:AddTag(shopStone, SHOP_STONE_TAG)
	local shopLabel = Instance.new("BillboardGui")
	shopLabel.Size = UDim2.fromOffset(160, 56)
	shopLabel.StudsOffset = Vector3.new(0, 9, 0)
	shopLabel.Adornee = shopStone
	shopLabel.Parent = parent
	local shl = Instance.new("TextLabel")
	shl.Size = UDim2.new(1, 0, 0.55, 0)
	shl.BackgroundTransparency = 1
	shl.Text = "SHOP"
	shl.TextColor3 = Color3.fromRGB(255, 215, 80)
	shl.TextStrokeTransparency = 0
	shl.Font = Enum.Font.GothamBlack
	shl.TextScaled = true
	shl.Parent = shopLabel
	local shlSub = Instance.new("TextLabel")
	shlSub.Size = UDim2.new(1, 0, 0.45, 0)
	shlSub.Position = UDim2.fromScale(0, 0.55)
	shlSub.BackgroundTransparency = 1
	shlSub.Text = "🔒 Coming Soon"
	shlSub.TextColor3 = Color3.fromRGB(200, 180, 140)
	shlSub.TextStrokeTransparency = 0.3
	shlSub.Font = Enum.Font.GothamBold
	shlSub.TextScaled = true
	shlSub.Parent = shopLabel
end

-- Portal disc to Arena. Visual only in Part A — Part E adds the Touched
-- teleport handler. Stored as a known Instance for Part E to find.
local function buildPortalToArena(parent: Instance): Part
	local portalPos = LAIR_CENTER + Vector3.new(0, FLOOR_THICKNESS / 2 + 0.5, -PORTAL_DISTANCE_FROM_CENTER)

	local portal = makePart("PortalToArena", parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 14, 14),
		CFrame = CFrame.new(portalPos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(100, 200, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CanCollide = false,
	})
	CollectionService:AddTag(portal, "DragonWarz_Portal_ToArena")

	-- Particle effect: swirling portal energy
	local attach = Instance.new("Attachment")
	attach.Parent = portal
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particles.Color = ColorSequence.new(Color3.fromRGB(150, 220, 255))
	particles.Size = NumberSequence.new(1.5, 0.3)
	particles.Transparency = NumberSequence.new(0.2, 1)
	particles.Lifetime = NumberRange.new(0.6, 1.2)
	particles.Rate = 80
	particles.Speed = NumberRange.new(2, 6)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Parent = attach

	-- Light source so the portal visibly illuminates the surrounding floor
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(120, 200, 255)
	light.Brightness = 5
	light.Range = 30
	light.Parent = portal

	-- Floating label
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 50)
	billboard.StudsOffset = Vector3.new(0, 12, 0)
	billboard.Adornee = portal
	billboard.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "ENTER ARENA"
	label.TextColor3 = Color3.fromRGB(180, 240, 255)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = billboard

	return portal
end

-- Sprint 8: ambient floating motes drifting through the Lair air. Pure
-- visual ambience — kid spends 30s+ in the Lair per round and the empty
-- air between the central pillar and the arches read as "static
-- decoration" without these. Motes use:
--   - Small Neon spheres (~1 stud) at random Y between floor and ~80
--     above so they fill the volume kids fly through.
--   - Element-color tints (Fire / Ice / Lightning / etc.) drawn from
--     ELEMENT_CYCLE_COLORS so they match the central pillar's palette.
--   - Slow random-walk drift via TweenService chain — each mote picks a
--     new target every 4-6 seconds and tweens there. Cheap (no
--     Heartbeat per-frame work).
--   - Transparency cycle so they fade in and out, hiding the destination
--     swaps and giving a "magical specks" feel rather than "jiggling
--     billiard balls".
local AMBIENT_MOTE_COUNT = 30
local AMBIENT_MOTE_RADIUS = 110 -- horizontal scatter (slightly wider than FLOOR_RADIUS)

local function buildAmbientMotes(parent: Instance)
	local TweenService = game:GetService("TweenService")
	for i = 1, AMBIENT_MOTE_COUNT do
		local color = ELEMENT_CYCLE_COLORS[((i - 1) % #ELEMENT_CYCLE_COLORS) + 1]
		local startAngle = math.random() * math.pi * 2
		local startDist = math.random() * AMBIENT_MOTE_RADIUS
		local startHeight = math.random(8, 70)
		local mote = makePart(`AmbientMote_{i}`, parent, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.new(LAIR_CENTER + Vector3.new(
				math.cos(startAngle) * startDist,
				startHeight,
				math.sin(startAngle) * startDist
			)),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.3,
			CanCollide = false,
		})

		-- Random-walk drift. Each mote runs its own tween chain on its own
		-- coroutine so they don't all swing in lockstep. task.wait() with
		-- a small jitter staggers their first tween starts so the swarm
		-- feels organic.
		task.delay(math.random() * 2, function()
			while mote.Parent do
				local angle = math.random() * math.pi * 2
				local dist = math.random() * AMBIENT_MOTE_RADIUS
				local height = math.random(8, 70)
				local target = CFrame.new(LAIR_CENTER + Vector3.new(
					math.cos(angle) * dist, height, math.sin(angle) * dist
				))
				local duration = 4 + math.random() * 2
				local tween = TweenService:Create(mote,
					TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ CFrame = target }
				)
				tween:Play()
				tween.Completed:Wait()
			end
		end)

		-- Transparency cycle so the mote fades in and out. Independent
		-- tween chain (different period from drift so they desync naturally
		-- and the swarm doesn't pulse as one).
		task.delay(math.random() * 1.5, function()
			while mote.Parent do
				local fadeOut = TweenService:Create(mote,
					TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Transparency = 0.85 }
				)
				fadeOut:Play()
				fadeOut.Completed:Wait()
				if not mote.Parent then break end
				local fadeIn = TweenService:Create(mote,
					TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Transparency = 0.3 }
				)
				fadeIn:Play()
				fadeIn.Completed:Wait()
			end
		end)
	end
end

function LairBuilder.build()
	local model = Instance.new("Model")
	model.Name = "Lair"
	CollectionService:AddTag(model, LAIR_TAG)
	model.Parent = workspace

	buildFloor(model)
	buildCentralPillar(model)
	buildElementArches(model)
	buildPracticeDummies(model)
	buildInteractionStones(model)
	buildPortalToArena(model)
	buildAmbientMotes(model) -- Sprint 8 eye candy

	print(`[LairBuilder] Crystal Lair built at {LAIR_CENTER}. {#spawnPoints} spawn points.`)
end

return LairBuilder
