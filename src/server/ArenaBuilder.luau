--!strict
-- Builds the Dragon Warz floating island arena.
-- Creates terrain, islands, skybox, and lighting at server startup.

local Lighting = game:GetService("Lighting")

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

	print("[ArenaBuilder] Arena built!")
end

return ArenaBuilder
