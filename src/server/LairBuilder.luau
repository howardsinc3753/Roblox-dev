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

local LairBuilder = {}

-- World-space constants. The Y=500 keeps the Lair high in the sky so it
-- visually reads as "above the chaos" — players literally look down at
-- the Arena clouds when they exit.
local LAIR_CENTER = Vector3.new(2000, 500, 0)
local FLOOR_RADIUS = 100
local FLOOR_THICKNESS = 6
local PORTAL_DISTANCE_FROM_CENTER = 70 -- portal sits at south edge of disc
local LAIR_TAG = "DragonWarz_Lair"

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

-- Build the stone disc floor. Cylinder rotated 90° around X axis to lay flat.
-- Glowing rune accents at cardinal compass points hint at the magic theme.
local function buildFloor(parent: Instance)
	local floor = makePart("LairFloor", parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(FLOOR_THICKNESS, FLOOR_RADIUS * 2, FLOOR_RADIUS * 2),
		CFrame = CFrame.new(LAIR_CENTER) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(80, 70, 90), -- weathered stone
		Material = Enum.Material.Slate,
		CanCollide = true, -- floor IS collidable (only piece that is)
	})

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

-- Central Crystal Pillar — placeholder cube cluster. Sprint 7 swaps the
-- mesh for a Meshy-generated "fantasy crystal cluster" hero piece.
local function buildCentralPillar(parent: Instance)
	-- Three stacked cubes of decreasing size — visually reads as a crystal
	-- formation even before the Meshy swap.
	local heights = { 6, 12, 24 }
	local sizes = { 14, 10, 6 }
	local colors = {
		Color3.fromRGB(100, 80, 200), -- base, deep purple
		Color3.fromRGB(180, 140, 255), -- mid, lavender
		Color3.fromRGB(240, 220, 255), -- top, almost white-glowing
	}
	local cumulativeHeight = FLOOR_THICKNESS / 2
	for i = 1, 3 do
		cumulativeHeight += heights[i] / 2
		makePart(`CrystalLayer_{i}`, parent, {
			Shape = Enum.PartType.Block,
			Size = Vector3.new(sizes[i], heights[i], sizes[i]),
			CFrame = CFrame.new(LAIR_CENTER + Vector3.new(0, cumulativeHeight, 0))
				* CFrame.Angles(0, math.rad((i - 1) * 30), 0), -- slight rotation per layer
			Color = colors[i],
			Material = Enum.Material.Neon,
			Transparency = 0.15,
		})
		cumulativeHeight += heights[i] / 2
	end

	-- Light source at the top of the pillar
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
		makePart(`Arch_{element.name}_Crystal`, parent, {
			Shape = Enum.PartType.Block,
			Size = Vector3.new(2, 3, 2),
			CFrame = CFrame.new(archCenter + Vector3.new(0, archHeight / 2 - 2, 0))
				* CFrame.Angles(math.rad(45), math.rad((i - 1) * 60), math.rad(45)),
			Color = element.color,
			Material = Enum.Material.Neon,
			Transparency = 0.1,
		})
	end
end

-- Practice dummies: 3 simple humanoid-shaped targets. Sprint 7 wires them
-- to take damage + heal; for V1 they're just visual placeholders.
local function buildPracticeDummies(parent: Instance)
	for i = 1, 3 do
		local angle = math.rad(60 + i * 50) -- arc on one side of the lair
		local pos = LAIR_CENTER + Vector3.new(
			math.cos(angle) * 50,
			FLOOR_THICKNESS / 2 + 5,
			math.sin(angle) * 50
		)
		-- Body
		makePart(`Dummy_{i}_Body`, parent, {
			Size = Vector3.new(4, 5, 4),
			CFrame = CFrame.new(pos),
			Color = Color3.fromRGB(150, 100, 80),
			Material = Enum.Material.Wood,
		})
		-- Head
		makePart(`Dummy_{i}_Head`, parent, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3, 3, 3),
			CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)),
			Color = Color3.fromRGB(200, 150, 120),
			Material = Enum.Material.Wood,
		})
		-- Floating "PRACTICE" label
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(120, 30)
		billboard.StudsOffset = Vector3.new(0, 4, 0)
		billboard.Adornee = parent:FindFirstChild(`Dummy_{i}_Head`)
		billboard.Parent = parent
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "PRACTICE"
		label.TextColor3 = Color3.fromRGB(220, 220, 220)
		label.TextStrokeTransparency = 0
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = billboard
	end
end

-- Stat Stone obelisk + Shop Stone obelisk. V1 visual placeholders; Sprint 7/9
-- add ProximityPrompt or Touched handlers that open the upgrade/shop UI.
local function buildInteractionStones(parent: Instance)
	-- Stat Stone (left of pillar)
	local statStone = makePart("StatStone", parent, {
		Size = Vector3.new(4, 14, 4),
		CFrame = CFrame.new(LAIR_CENTER + Vector3.new(-50, FLOOR_THICKNESS / 2 + 7, 0)),
		Color = Color3.fromRGB(50, 70, 110),
		Material = Enum.Material.Slate,
	})
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

	-- Shop Stone (right of pillar)
	local shopStone = makePart("ShopStone", parent, {
		Size = Vector3.new(4, 14, 4),
		CFrame = CFrame.new(LAIR_CENTER + Vector3.new(50, FLOOR_THICKNESS / 2 + 7, 0)),
		Color = Color3.fromRGB(110, 80, 40),
		Material = Enum.Material.Slate,
	})
	local shopRunes = makePart("ShopStoneRunes", parent, {
		Size = Vector3.new(4.1, 8, 0.2),
		CFrame = shopStone.CFrame * CFrame.new(0, 0, 2.05),
		Color = Color3.fromRGB(255, 215, 80),
		Material = Enum.Material.Neon,
		Transparency = 0.3,
	})
	local shopLabel = Instance.new("BillboardGui")
	shopLabel.Size = UDim2.fromOffset(140, 40)
	shopLabel.StudsOffset = Vector3.new(0, 9, 0)
	shopLabel.Adornee = shopStone
	shopLabel.Parent = parent
	local shl = Instance.new("TextLabel")
	shl.Size = UDim2.fromScale(1, 1)
	shl.BackgroundTransparency = 1
	shl.Text = "SHOP"
	shl.TextColor3 = Color3.fromRGB(255, 215, 80)
	shl.TextStrokeTransparency = 0
	shl.Font = Enum.Font.GothamBlack
	shl.TextScaled = true
	shl.Parent = shopLabel
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

	print(`[LairBuilder] Crystal Lair built at {LAIR_CENTER}. {#spawnPoints} spawn points.`)
end

return LairBuilder
