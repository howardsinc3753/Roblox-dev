--!strict
-- Creates and manages dragon character models for players.
-- Uses real Meshy-generated meshes when DragonConfig has a meshAssetId,
-- otherwise falls back to placeholder Part-based dragons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

local DragonConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("DragonConfig"))

-- Cache loaded mesh templates per dragonId (avoid re-downloading every spawn)
local meshCache: { [string]: Model } = {}

local DragonSpawner = {}

-- Spawn points (positions in the arena)
local SPAWN_POINTS = {
	Vector3.new(0, 50, 0),
	Vector3.new(100, 60, 100),
	Vector3.new(-100, 55, 100),
	Vector3.new(100, 65, -100),
	Vector3.new(-100, 50, -100),
	Vector3.new(0, 70, 150),
}

local function getRandomSpawnPoint(): Vector3
	return SPAWN_POINTS[math.random(1, #SPAWN_POINTS)]
end

-- Build a simple dragon model from parts (placeholder until meshes)
local function buildDragonModel(dragonId: string, player: Player): Model
	local dragon = DragonConfig[dragonId]
	if not dragon then
		dragon = DragonConfig.Ember
	end

	local model = Instance.new("Model")
	model.Name = `Dragon_{player.Name}`

	-- Body (main part — acts as HumanoidRootPart)
	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Size = Vector3.new(6, 4, 10)
	body.Shape = Enum.PartType.Block
	body.Color = dragon.color
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = false
	body.CanCollide = true
	body.Parent = model

	-- Head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(3, 3, 4)
	head.Shape = Enum.PartType.Ball
	head.Color = dragon.color
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = false
	head.CanCollide = false
	head.Parent = model

	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = body
	headWeld.Part1 = head
	headWeld.Parent = head
	head.CFrame = body.CFrame * CFrame.new(0, 1, -6)

	-- Wings (left)
	local wingL = Instance.new("Part")
	wingL.Name = "WingLeft"
	wingL.Size = Vector3.new(8, 0.5, 5)
	wingL.Color = dragon.secondaryColor
	wingL.Material = Enum.Material.SmoothPlastic
	wingL.Anchored = false
	wingL.CanCollide = false
	wingL.Parent = model

	local wingLWeld = Instance.new("WeldConstraint")
	wingLWeld.Part0 = body
	wingLWeld.Part1 = wingL
	wingLWeld.Parent = wingL
	wingL.CFrame = body.CFrame * CFrame.new(-7, 1, 0)

	-- Wings (right)
	local wingR = Instance.new("Part")
	wingR.Name = "WingRight"
	wingR.Size = Vector3.new(8, 0.5, 5)
	wingR.Color = dragon.secondaryColor
	wingR.Material = Enum.Material.SmoothPlastic
	wingR.Anchored = false
	wingR.CanCollide = false
	wingR.Parent = model

	local wingRWeld = Instance.new("WeldConstraint")
	wingRWeld.Part0 = body
	wingRWeld.Part1 = wingR
	wingRWeld.Parent = wingR
	wingR.CFrame = body.CFrame * CFrame.new(7, 1, 0)

	-- Tail
	local tail = Instance.new("Part")
	tail.Name = "Tail"
	tail.Size = Vector3.new(2, 2, 8)
	tail.Color = dragon.secondaryColor
	tail.Material = Enum.Material.SmoothPlastic
	tail.Anchored = false
	tail.CanCollide = false
	tail.Parent = model

	local tailWeld = Instance.new("WeldConstraint")
	tailWeld.Part0 = body
	tailWeld.Part1 = tail
	tailWeld.Parent = tail
	tail.CFrame = body.CFrame * CFrame.new(0, 0, 8)

	-- Humanoid (required for Roblox character system)
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = dragon.health
	humanoid.Health = dragon.health
	humanoid.WalkSpeed = 0 -- dragons fly, don't walk
	humanoid.JumpPower = 0
	humanoid.Parent = model

	-- Name tag
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "NameTag"
	billboardGui.Size = UDim2.fromOffset(200, 50)
	billboardGui.StudsOffset = Vector3.new(0, 5, 0)
	billboardGui.Adornee = body
	billboardGui.Parent = model

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 0.6)
	nameLabel.Text = player.Name
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = billboardGui

	local dragonLabel = Instance.new("TextLabel")
	dragonLabel.Size = UDim2.fromScale(1, 0.4)
	dragonLabel.Position = UDim2.fromScale(0, 0.6)
	dragonLabel.Text = `{dragon.name} ({dragon.element})`
	dragonLabel.TextColor3 = dragon.color
	dragonLabel.TextStrokeTransparency = 0
	dragonLabel.BackgroundTransparency = 1
	dragonLabel.TextScaled = true
	dragonLabel.Font = Enum.Font.Gotham
	dragonLabel.Parent = billboardGui

	-- Health bar
	local healthGui = Instance.new("BillboardGui")
	healthGui.Name = "HealthBar"
	healthGui.Size = UDim2.fromOffset(150, 15)
	healthGui.StudsOffset = Vector3.new(0, 4, 0)
	healthGui.Adornee = body
	healthGui.Parent = model

	local healthBg = Instance.new("Frame")
	healthBg.Size = UDim2.fromScale(1, 1)
	healthBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	healthBg.BorderSizePixel = 0
	healthBg.Parent = healthGui

	local healthCorner = Instance.new("UICorner")
	healthCorner.CornerRadius = UDim.new(0, 4)
	healthCorner.Parent = healthBg

	local healthFill = Instance.new("Frame")
	healthFill.Name = "Fill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = healthFill

	model.PrimaryPart = body
	return model
end

-- Load a Meshy mesh from Roblox asset ID. Returns the loaded mesh as a Model
-- (cloned from a cached template), or nil on failure.
local function loadMeshTemplate(dragonId: string, assetId: number): Model?
	if meshCache[dragonId] then
		return meshCache[dragonId]:Clone()
	end

	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)

	if not ok or not result then
		warn(`[DragonSpawner] Failed to load mesh for {dragonId} (assetId={assetId}): {result}`)
		return nil
	end

	-- LoadAsset returns a Model wrapper; the actual content is inside
	local container = result :: Model
	local meshContent: Model? = nil

	for _, child in container:GetChildren() do
		if child:IsA("Model") then
			meshContent = child
			break
		end
	end

	-- Sometimes the mesh is parented directly to the container
	if not meshContent then
		meshContent = container
	end

	meshCache[dragonId] = meshContent :: Model
	container.Parent = nil
	return (meshContent :: Model):Clone()
end

-- Attach the loaded Meshy mesh to a player's dragon model as visual.
-- Welds all parts of the mesh to the body (HumanoidRootPart equivalent),
-- removes placeholder visual parts (head, wings, tail), keeps body transparent.
local function attachMeshVisual(dragonModel: Model, meshAssetId: number, dragonId: string, scale: number)
	local meshTemplate = loadMeshTemplate(dragonId, meshAssetId)
	if not meshTemplate then return end

	local body = dragonModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not body then return end

	-- Hide the placeholder visual parts (keep body for physics, hide visually)
	for _, partName in { "HumanoidRootPart", "Head", "WingLeft", "WingRight", "Tail" } do
		local part = dragonModel:FindFirstChild(partName) :: BasePart?
		if part then
			part.Transparency = 1
			-- Disable the placeholder body's color so weld clipping doesn't show
		end
	end

	-- Scale the mesh
	if meshTemplate:IsA("Model") then
		meshTemplate:ScaleTo(scale)
	end

	-- Position the mesh at the body and weld all parts to it
	local meshCenter: Vector3 = body.Position
	if meshTemplate:IsA("Model") then
		meshTemplate:PivotTo(CFrame.new(meshCenter))
	end

	-- Weld each part of the mesh to the body
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

	meshTemplate.Name = "MeshyVisual"
	meshTemplate.Parent = dragonModel
end

function DragonSpawner.spawn(player: Player, dragonId: string): Model
	-- Remove old character if any
	if player.Character then
		player.Character:Destroy()
	end

	local model = buildDragonModel(dragonId, player)
	local spawnPos = getRandomSpawnPoint()
	model:PivotTo(CFrame.new(spawnPos))
	model.Parent = game.Workspace

	-- If this dragon has a real Meshy mesh, attach it as visual layer
	local dragonCfg = DragonConfig[dragonId]
	if dragonCfg and dragonCfg.meshAssetId then
		attachMeshVisual(model, dragonCfg.meshAssetId, dragonId, dragonCfg.meshScale or 1)
	end

	player.Character = model

	-- Set up constraints for flight (modern API, replaces deprecated BodyMovers)
	local rootPart = model.PrimaryPart :: BasePart
	rootPart.Anchored = false

	-- Attachment for constraints
	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = rootPart

	-- LinearVelocity for movement (replaces BodyVelocity)
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "FlightVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = math.huge
	linearVelocity.VectorVelocity = Vector3.zero
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.Parent = rootPart

	-- AlignOrientation for rotation (replaces BodyGyro)
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "FlightGyro"
	alignOrientation.Attachment0 = attachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.MaxTorque = math.huge
	alignOrientation.Responsiveness = 20
	alignOrientation.CFrame = CFrame.new(spawnPos)
	alignOrientation.Parent = rootPart

	return model
end

function DragonSpawner.getRandomSpawnPoint(): Vector3
	return getRandomSpawnPoint()
end

return DragonSpawner
