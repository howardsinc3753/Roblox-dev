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

-- Central Pillar: try Meshy AI crystal tower first; fall back to a
-- programmatic stacked-cube cluster if asset load fails. Either way the
-- centerpiece reads as the magical focal point of the Lair.
local function buildCentralPillar(parent: Instance)
	local pillarBase = LAIR_CENTER + Vector3.new(0, FLOOR_THICKNESS / 2, 0)

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
		light.Color = Color3.fromRGB(200, 180, 255)
		light.Brightness = 5
		light.Range = 80
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
