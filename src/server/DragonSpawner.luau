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

	-- Wire the overhead health bar to the Humanoid. Humanoid.HealthChanged
	-- fires every time CombatManager.applyDamage runs syncHealthToHumanoid.
	-- Without this hookup, the Fill stays at 100% forever and kids can't
	-- tell when other players are getting low on HP (NPC health bars work
	-- because NPCManager.applyDamage updates them directly in code).
	-- Color shifts green→yellow→red so the bar reads at a glance.
	humanoid.HealthChanged:Connect(function(newHealth: number)
		local pct = math.clamp(newHealth / humanoid.MaxHealth, 0, 1)
		healthFill.Size = UDim2.fromScale(pct, 1)
		if pct > 0.5 then
			healthFill.BackgroundColor3 = Color3.fromRGB(50, 200, 50) -- green
		elseif pct > 0.25 then
			healthFill.BackgroundColor3 = Color3.fromRGB(255, 200, 50) -- yellow
		else
			healthFill.BackgroundColor3 = Color3.fromRGB(255, 50, 50) -- red
		end
	end)

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
-- Architecture: mesh parts weld to an invisible MeshAnchor part, NOT to the
-- body directly. A Motor6D joint connects body → MeshAnchor. FlightController
-- drives Motor6D.Transform each frame to apply wobble/tilt to the visible mesh
-- without rotating the body itself. This keeps the body's rotation (which the
-- camera follows and breath aim depends on) rock-steady — the camera no longer
-- shakes when the dragon wobbles.
local function attachMeshVisual(dragonModel: Model, meshAssetId: number, dragonId: string, scale: number)
	local meshTemplate = loadMeshTemplate(dragonId, meshAssetId)
	if not meshTemplate then return end

	local body = dragonModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not body then return end

	-- Hide the placeholder visual parts (body stays for physics, hidden visually)
	for _, partName in { "HumanoidRootPart", "Head", "WingLeft", "WingRight", "Tail" } do
		local part = dragonModel:FindFirstChild(partName) :: BasePart?
		if part then
			part.Transparency = 1
		end
	end

	-- MeshAnchor: invisible carrier part that owns the mesh.
	-- Mesh BaseParts weld to this. The Motor6D drives this part's offset from
	-- the body, which moves the welded mesh with it.
	local meshAnchor = Instance.new("Part")
	meshAnchor.Name = "MeshAnchor"
	meshAnchor.Size = Vector3.new(0.5, 0.5, 0.5)
	meshAnchor.Transparency = 1
	meshAnchor.CanCollide = false
	meshAnchor.Massless = true
	meshAnchor.Anchored = false
	meshAnchor.CFrame = body.CFrame
	meshAnchor.Parent = dragonModel

	-- Motor6D: client-driven joint for visual-only wobble/tilt.
	-- FlightController writes to Transform every frame on Heartbeat.
	local meshMotor = Instance.new("Motor6D")
	meshMotor.Name = "MeshMotor"
	meshMotor.Part0 = body
	meshMotor.Part1 = meshAnchor
	meshMotor.C0 = CFrame.new(0, 0, 0)
	meshMotor.C1 = CFrame.new(0, 0, 0)
	meshMotor.Parent = body

	-- Scale + position the mesh
	if meshTemplate:IsA("Model") then
		meshTemplate:ScaleTo(scale)
		meshTemplate:PivotTo(body.CFrame)
	end

	-- Parent BEFORE creating welds. Roblox tolerates welds across nil-parent
	-- parts in practice, but it's fragile — keep weld creation inside the tree.
	meshTemplate.Name = "MeshyVisual"
	meshTemplate.Parent = dragonModel

	-- Weld every mesh BasePart to MeshAnchor (NOT body). This is the key
	-- architectural change — driving Motor6D.Transform now rotates the entire
	-- mesh as one rigid body, while the actual physics body stays steady.
	for _, descendant in meshTemplate:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = meshAnchor
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end

	-- Pivot offset: rotate the mesh around its visual center, not the body's
	-- origin. Without this, wobble looks like the dragon is swinging on a
	-- stick (Meshy meshes commonly export with pivot at bbox corner, not
	-- geometric center). Setting C0 = C1 keeps MeshAnchor.CFrame at body.CFrame
	-- when Transform = identity, but moves the rotation pivot to the visual
	-- center for any non-identity Transform.
	if meshTemplate:IsA("Model") then
		local meshCF, _meshSize = meshTemplate:GetBoundingBox()
		local localOffset = body.CFrame:PointToObjectSpace(meshCF.Position)
		local pivotOffset = CFrame.new(localOffset)
		meshMotor.C0 = pivotOffset
		meshMotor.C1 = pivotOffset
	end
end

-- Add a colored Trail effect that streams behind the dragon as it flies.
-- The trail uses the dragon's element color so each dragon has a distinct
-- visual signature in the air. Replicates from server so all clients see
-- every dragon's trail (not just their own).
local function attachTrailEffect(dragonModel: Model, dragon: any)
	local body = dragonModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not body then return end

	-- Two attachments: one in front, one behind. The trail draws between them.
	local frontAttach = Instance.new("Attachment")
	frontAttach.Name = "TrailFront"
	frontAttach.Position = Vector3.new(0, 0, 2)
	frontAttach.Parent = body

	local backAttach = Instance.new("Attachment")
	backAttach.Name = "TrailBack"
	backAttach.Position = Vector3.new(0, 0, -2)
	backAttach.Parent = body

	local trail = Instance.new("Trail")
	trail.Name = "FlightTrail"
	trail.Attachment0 = frontAttach
	trail.Attachment1 = backAttach
	trail.Lifetime = 1.2
	trail.MinLength = 0.05
	trail.LightEmission = 0.6
	trail.LightInfluence = 0
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, dragon.color),
		ColorSequenceKeypoint.new(0.5, dragon.secondaryColor),
		ColorSequenceKeypoint.new(1, dragon.color),
	})
	trail.Parent = body
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

	-- Trail effect for in-air visual flair (works for both placeholder and Meshy dragons)
	if dragonCfg then
		attachTrailEffect(model, dragonCfg)
	end

	-- Constraints created BEFORE player.Character = model. Otherwise the client
	-- briefly receives a character without flight constraints and FlightController
	-- silently no-ops on early-return for several frames (worse on dragon-swap).
	local rootPart = model.PrimaryPart :: BasePart
	rootPart.Anchored = false

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
	alignOrientation.Responsiveness = 20
	alignOrientation.CFrame = CFrame.new(spawnPos)
	alignOrientation.Parent = rootPart

	-- Character assignment LAST: client receives complete model with constraints
	-- already attached, so FlightController.Heartbeat sees them on first tick.
	player.Character = model

	return model
end

function DragonSpawner.getRandomSpawnPoint(): Vector3
	return getRandomSpawnPoint()
end

return DragonSpawner
