--!strict
-- Builds the Dragon Warz floating island arena.
-- Creates terrain, islands, skybox, and lighting at server startup.

local Lighting = game:GetService("Lighting")
local InsertService = game:GetService("InsertService")

-- Hero piece asset IDs (Meshy + Toolbox). Slot a placeholder cylinder
-- gets replaced by one of these; falls back to the cylinder if load fails.
local TOWER_ASSET_GUARD = 101559450428915 -- guard tower
local TOWER_ASSET_WIZARD = 5408278132 -- wizard tower
local SKY_ATMOSPHERE_ASSET = 4607457995 -- Atmosphere/Sky preset, parented to Lighting
local GRASS_BASE_ASSET = 12132147781 -- big grass platform, placed far below for ground feel
local SKY_CASTLE_ASSET = 108721507426018 -- floating castle, replaces placeholder block+spires at arena center

-- Loads a Roblox Model asset, scales + positions it, anchors all parts,
-- and parents it into Workspace. Returns the cloned model or nil on
-- failure (caller falls back to programmatic placeholder geometry).
local function loadHeroPiece(assetId: number, targetCFrame: CFrame, scale: number?): Model?
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not result then
		warn(`[ArenaBuilder] Failed to load hero asset {assetId}: {result}`)
		return nil
	end
	local container = result :: Model
	-- LoadAsset wraps the actual Model in a container Model. Find the inner
	-- one. If the asset is a single MeshPart, the container itself works.
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
			-- Solid towers act as cover — dragons must dive AROUND or
			-- OVER them, not through them. That's the whole point of
			-- vertical structures in aerial combat. Initially had this
			-- as false; user feedback was "I can fly through walls."
			descendant.CanCollide = true
		end
	end
	cloned.Parent = workspace
	return cloned
end

local ArenaBuilder = {}

local function createIsland(position: Vector3, size: Vector3, color: Color3, material: Enum.Material)
	local island = Instance.new("Part")
	island.Name = "Island"
	island.Size = size
	island.Position = position
	island.Color = color
	island.Material = material
	island.Anchored = true
	island.CanCollide = true
	island.Parent = game.Workspace
	return island
end

local function createDecoration(position: Vector3, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?)
	local part = Instance.new("Part")
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = true
	part.Parent = game.Workspace
	return part
end

function ArenaBuilder.build()
	-- Remove default baseplate
	local baseplate = game.Workspace:FindFirstChild("Baseplate")
	if baseplate then baseplate:Destroy() end
	local spawnLocation = game.Workspace:FindFirstChild("SpawnLocation")
	if spawnLocation then spawnLocation:Destroy() end

	-- === LIGHTING / SKYBOX ===
	Lighting.ClockTime = 17.5 -- sunset
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(60, 40, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(100, 80, 120)
	Lighting.FogEnd = 2000
	Lighting.FogColor = Color3.fromRGB(180, 120, 200)

	-- Atmosphere
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(200, 150, 220)
	atmosphere.Decay = Color3.fromRGB(100, 60, 130)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 2
	atmosphere.Parent = Lighting

	-- Sky
	local sky = Instance.new("Sky")
	sky.SunAngularSize = 15
	sky.MoonAngularSize = 10
	sky.StarCount = 3000
	sky.SkyboxBk = ""
	sky.SkyboxDn = ""
	sky.SkyboxFt = ""
	sky.SkyboxLf = ""
	sky.SkyboxRt = ""
	sky.SkyboxUp = ""
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	-- Bloom for glow effects
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.3
	bloom.Size = 24
	bloom.Threshold = 1.5
	bloom.Parent = Lighting

	-- Color correction for dramatic sunset feel
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0.02
	cc.Contrast = 0.1
	cc.Saturation = 0.2
	cc.TintColor = Color3.fromRGB(255, 230, 220)
	cc.Parent = Lighting

	-- === MAIN ISLAND (center) ===
	local mainIsland = createIsland(
		Vector3.new(0, 20, 0),
		Vector3.new(120, 20, 120),
		Color3.fromRGB(80, 100, 60),
		Enum.Material.Grass
	)
	mainIsland.Name = "MainIsland"

	-- Rock underside
	createDecoration(
		Vector3.new(0, 5, 0),
		Vector3.new(100, 15, 100),
		Color3.fromRGB(120, 100, 80),
		Enum.Material.Slate
	)

	-- Center crystal
	local crystal = Instance.new("Part")
	crystal.Name = "CenterCrystal"
	crystal.Size = Vector3.new(8, 25, 8)
	crystal.Position = Vector3.new(0, 45, 0)
	crystal.Color = Color3.fromRGB(100, 200, 255)
	crystal.Material = Enum.Material.Neon
	crystal.Transparency = 0.2
	crystal.Anchored = true
	crystal.CanCollide = false
	crystal.Parent = game.Workspace

	-- Crystal glow with PointLight
	local pointLight = Instance.new("PointLight")
	pointLight.Color = Color3.fromRGB(100, 200, 255)
	pointLight.Brightness = 3
	pointLight.Range = 40
	pointLight.Parent = crystal

	-- === SURROUNDING ISLANDS ===
	local islandConfigs = {
		{ pos = Vector3.new(150, 40, 100), size = Vector3.new(60, 12, 50), color = Color3.fromRGB(90, 110, 65) },
		{ pos = Vector3.new(-150, 50, 100), size = Vector3.new(50, 10, 60), color = Color3.fromRGB(85, 105, 60) },
		{ pos = Vector3.new(130, 60, -120), size = Vector3.new(55, 14, 45), color = Color3.fromRGB(95, 115, 70) },
		{ pos = Vector3.new(-120, 35, -130), size = Vector3.new(65, 11, 55), color = Color3.fromRGB(80, 100, 55) },
		{ pos = Vector3.new(0, 70, 180), size = Vector3.new(45, 10, 45), color = Color3.fromRGB(90, 110, 65) },
		{ pos = Vector3.new(-80, 55, 0), size = Vector3.new(40, 8, 40), color = Color3.fromRGB(85, 105, 60) },
		{ pos = Vector3.new(80, 45, -60), size = Vector3.new(35, 9, 35), color = Color3.fromRGB(95, 115, 70) },
	}

	for i, config in islandConfigs do
		local island = createIsland(config.pos, config.size, config.color, Enum.Material.Grass)
		island.Name = `Island_{i}`

		-- Rock underside for each
		createDecoration(
			config.pos - Vector3.new(0, config.size.Y * 0.6, 0),
			Vector3.new(config.size.X * 0.7, config.size.Y * 0.8, config.size.Z * 0.7),
			Color3.fromRGB(120, 100, 80),
			Enum.Material.Slate
		)

		-- Random tree/rock decorations
		if i % 2 == 0 then
			-- Tree trunk
			createDecoration(
				config.pos + Vector3.new(math.random(-10, 10), config.size.Y / 2 + 5, math.random(-10, 10)),
				Vector3.new(3, 10, 3),
				Color3.fromRGB(100, 70, 40),
				Enum.Material.Wood
			)
			-- Tree canopy
			createDecoration(
				config.pos + Vector3.new(math.random(-10, 10), config.size.Y / 2 + 12, math.random(-10, 10)),
				Vector3.new(10, 8, 10),
				Color3.fromRGB(40, 130, 40),
				Enum.Material.Grass,
				Enum.PartType.Ball
			)
		else
			-- Rock formation
			createDecoration(
				config.pos + Vector3.new(math.random(-8, 8), config.size.Y / 2 + 3, math.random(-8, 8)),
				Vector3.new(6, 6, 6),
				Color3.fromRGB(140, 130, 110),
				Enum.Material.Slate,
				Enum.PartType.Ball
			)
		end
	end

	-- === SMALL FLOATING ROCKS (ambient) ===
	for i = 1, 15 do
		local rock = Instance.new("Part")
		rock.Name = `FloatingRock_{i}`
		rock.Size = Vector3.new(math.random(3, 8), math.random(3, 8), math.random(3, 8))
		rock.Position = Vector3.new(
			math.random(-200, 200),
			math.random(30, 90),
			math.random(-200, 200)
		)
		rock.Color = Color3.fromRGB(130 + math.random(-20, 20), 110 + math.random(-20, 20), 90 + math.random(-20, 20))
		rock.Material = Enum.Material.Slate
		rock.Anchored = true
		rock.CanCollide = true
		rock.Parent = game.Workspace
	end

	-- === CLOUD LAYER (below islands) ===
	for i = 1, 20 do
		local cloud = Instance.new("Part")
		cloud.Name = `Cloud_{i}`
		cloud.Shape = Enum.PartType.Ball
		cloud.Size = Vector3.new(
			math.random(30, 80),
			math.random(5, 15),
			math.random(30, 80)
		)
		cloud.Position = Vector3.new(
			math.random(-300, 300),
			math.random(-20, 5),
			math.random(-300, 300)
		)
		cloud.Color = Color3.fromRGB(220, 200, 230)
		cloud.Material = Enum.Material.SmoothPlastic
		cloud.Transparency = 0.6
		cloud.Anchored = true
		cloud.CanCollide = false
		cloud.Parent = game.Workspace
	end

	-- === KILL BOUNDARY ===
	local killZone = Instance.new("Part")
	killZone.Name = "KillBoundary"
	killZone.Size = Vector3.new(1000, 1, 1000)
	killZone.Position = Vector3.new(0, -50, 0)
	killZone.Transparency = 1
	killZone.Anchored = true
	killZone.CanCollide = false
	killZone.Parent = game.Workspace

	-- ============================================================
	-- Sprint 5 Part B: Sky Kingdom upgrade
	-- Tall structures + cloud platforms + central placeholder give
	-- the arena verticality + cover for aerial dogfights. Without
	-- these, players just zoom in open sky with nothing to dive
	-- around, hide behind, or use as a landmark.
	-- ============================================================

	-- Sky Towers: 5 vertical landmarks at varied positions + heights.
	-- Towers 1-2 use Toolbox/Meshy hero assets (guard + wizard towers);
	-- towers 3-5 fall back to programmatic cylinders. Hero load failures
	-- gracefully degrade to the cylinder fallback (LoadAsset can fail in
	-- Studio without the asset being permission-granted).
	local towerPositions = {
		-- Hero asset towers: scale 2 (originally 8 was way too large per QA).
		-- Tweak this number if towers still appear oversized or too small.
		{ pos = Vector3.new(150, 0, 0), height = 130, asset = TOWER_ASSET_GUARD, scale = 2 },
		{ pos = Vector3.new(-160, 0, 80), height = 110, asset = TOWER_ASSET_WIZARD, scale = 2 },
		{ pos = Vector3.new(80, 60, -180), height = 150, asset = nil },
		{ pos = Vector3.new(-100, 40, -150), height = 120, asset = nil },
		{ pos = Vector3.new(180, 80, 170), height = 100, asset = nil },
	}
	for i, tower in towerPositions do
		local heroLoaded = false
		if tower.asset then
			local hero = loadHeroPiece(
				tower.asset,
				CFrame.new(tower.pos),
				tower.scale
			)
			if hero then
				hero.Name = `SkyTower_{i}_Hero`
				heroLoaded = true
			end
		end

		if not heroLoaded then
			-- Fallback cylinder body
			local body = Instance.new("Part")
			body.Name = `SkyTower_{i}_Body`
			body.Shape = Enum.PartType.Cylinder
			body.Size = Vector3.new(tower.height, 22, 22)
			body.CFrame = CFrame.new(tower.pos + Vector3.new(0, tower.height / 2, 0))
				* CFrame.Angles(0, 0, math.rad(90))
			body.Color = Color3.fromRGB(80, 75, 90)
			body.Material = Enum.Material.Slate
			body.Anchored = true
			body.CanCollide = true
			body.Parent = game.Workspace

			-- Emissive crown ring at the top — landmark in flight
			local crown = Instance.new("Part")
			crown.Name = `SkyTower_{i}_Crown`
			crown.Shape = Enum.PartType.Cylinder
			crown.Size = Vector3.new(3, 28, 28)
			crown.CFrame = CFrame.new(tower.pos + Vector3.new(0, tower.height + 1, 0))
				* CFrame.Angles(0, 0, math.rad(90))
			crown.Color = Color3.fromRGB(255, 200, 80)
			crown.Material = Enum.Material.Neon
			crown.Transparency = 0.2
			crown.Anchored = true
			crown.CanCollide = false
			crown.Parent = game.Workspace
		end
	end

	-- Cloud Platforms: 10 flat disc Parts at mid-altitudes scattered
	-- around the arena. Mid-altitude perches for resting + breaking
	-- off the chase. CanCollide so dragons can land on them.
	local cloudCount = 10
	for i = 1, cloudCount do
		local angle = (i - 1) * math.pi * 2 / cloudCount + math.random() * 0.4
		local radius = 60 + math.random(0, 100)
		local height = 60 + math.random(0, 80)
		local cloud = Instance.new("Part")
		cloud.Name = `CloudPlatform_{i}`
		cloud.Shape = Enum.PartType.Cylinder
		cloud.Size = Vector3.new(2, 24 + math.random(0, 12), 24 + math.random(0, 12))
		cloud.CFrame = CFrame.new(
			math.cos(angle) * radius,
			height,
			math.sin(angle) * radius
		) * CFrame.Angles(0, 0, math.rad(90))
		cloud.Color = Color3.fromRGB(240, 245, 255)
		cloud.Material = Enum.Material.SmoothPlastic
		cloud.Transparency = 0.6 -- bumped from 0.15: more cloud-like, less "white disk"
		cloud.Anchored = true
		-- CanCollide=false (was true). User feedback: "white disk you can't
		-- fly through" felt like solid scenery, not cloud. Decorative-only
		-- now — dragons can fly straight through, removes the navigation
		-- frustration. Lose the "land on a cloud" feature; gain the freedom.
		cloud.CanCollide = false
		cloud.Parent = game.Workspace
	end

	-- Sky Atmosphere preset (user-supplied asset). LoadAsset returns a Model
	-- wrapper containing whatever atmospheric instances were saved (Atmosphere,
	-- Sky/Skybox, possibly ColorCorrectionEffect). We extract those and parent
	-- them to Lighting where Roblox expects them. Existing default Atmosphere
	-- (if any) gets replaced — only one Atmosphere instance is honored.
	local atmoOk, atmoResult = pcall(function()
		return InsertService:LoadAsset(SKY_ATMOSPHERE_ASSET)
	end)
	if atmoOk and atmoResult then
		for _, instance in atmoResult:GetDescendants() do
			if instance:IsA("Atmosphere") or instance:IsA("Sky") or instance:IsA("Clouds") then
				-- Remove any existing same-class instance under Lighting first
				for _, existing in Lighting:GetChildren() do
					if existing.ClassName == instance.ClassName then
						existing:Destroy()
					end
				end
				instance:Clone().Parent = Lighting
			end
		end
		atmoResult:Destroy()
	else
		warn(`[ArenaBuilder] Failed to load Sky Atmosphere asset {SKY_ATMOSPHERE_ASSET}: {atmoResult}`)
	end

	-- Grass Base: huge platform placed far below the floating arena. Gives
	-- the world a sense of "down there's the ground" — fixes the "everything
	-- floats in nothing" feel. Players can't reach it (kill boundary at
	-- Y=-50 stops them well before this), pure visual atmosphere.
	local grassBase = loadHeroPiece(
		GRASS_BASE_ASSET,
		CFrame.new(0, -300, 0),
		8 -- scale; tune if too small/large
	)
	if grassBase then
		grassBase.Name = "WorldGroundGrass"
	end

	-- Sky Castle: try the user-supplied hero asset first; fall back to a
	-- programmatic block-and-spires placeholder if the asset fails to load.
	local castleHero = loadHeroPiece(
		SKY_CASTLE_ASSET,
		CFrame.new(0, 130, 0),
		10 -- scale; tune if asset is too small/large
	)
	if castleHero then
		castleHero.Name = "SkyCastleHero"
	else
		-- Fallback placeholder block + 4 spires (original Sprint 5 Part B
		-- programmatic stand-in)
		local castleBase = Instance.new("Part")
		castleBase.Name = "SkyCastlePlaceholder"
		castleBase.Size = Vector3.new(60, 40, 60)
		castleBase.CFrame = CFrame.new(0, 130, 0)
		castleBase.Color = Color3.fromRGB(100, 90, 110)
		castleBase.Material = Enum.Material.Slate
		castleBase.Anchored = true
		castleBase.CanCollide = true
		castleBase.Parent = game.Workspace

		for i = 0, 3 do
			local angle = math.rad(45 + i * 90)
			local spire = Instance.new("Part")
			spire.Name = `SkyCastle_Spire_{i + 1}`
			spire.Shape = Enum.PartType.Cylinder
			spire.Size = Vector3.new(30, 6, 6)
			spire.CFrame = CFrame.new(
				math.cos(angle) * 22,
				130 + 35,
				math.sin(angle) * 22
			) * CFrame.Angles(0, 0, math.rad(90))
			spire.Color = Color3.fromRGB(120, 110, 130)
			spire.Material = Enum.Material.Slate
			spire.Anchored = true
			spire.CanCollide = false
			spire.Parent = game.Workspace
		end
	end

	-- Glowing crystal at the very top of the castle — visible from anywhere
	-- in the arena, doubles as the "look here" landmark for new players
	local castleCrystal = Instance.new("Part")
	castleCrystal.Name = "SkyCastle_Crystal"
	castleCrystal.Shape = Enum.PartType.Block
	castleCrystal.Size = Vector3.new(8, 18, 8)
	castleCrystal.CFrame = CFrame.new(0, 175, 0) * CFrame.Angles(0, math.rad(45), 0)
	castleCrystal.Color = Color3.fromRGB(180, 220, 255)
	castleCrystal.Material = Enum.Material.Neon
	castleCrystal.Transparency = 0.1
	castleCrystal.Anchored = true
	castleCrystal.CanCollide = false
	castleCrystal.Parent = game.Workspace

	local crystalLight = Instance.new("PointLight")
	crystalLight.Color = Color3.fromRGB(180, 220, 255)
	crystalLight.Brightness = 6
	crystalLight.Range = 80
	crystalLight.Parent = castleCrystal

	print("[ArenaBuilder] Arena built! (Sky Kingdom: 5 towers, 10 clouds, central castle)")
end

return ArenaBuilder
