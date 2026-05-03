--!strict
-- Dragon mesh validation: spawns all 6 dragons in a row and prints stats.
-- HOW TO USE: drag this file into Studio's ServerScriptService manually
-- (don't sync via Rojo — it's a one-shot validation, not game code), then
-- F5 playtest. Output console will show the result for each dragon. Visually
-- check Studio that all 6 dragons appear in a row at y=80, sized similarly.
--
-- Looking for:
-- - InsertService:LoadAsset succeeds for every dragon (no warns in Output)
-- - Each mesh actually has BaseParts (not empty Model wrapper)
-- - Bounding boxes are roughly the same size (within ~30% — Meshy meshes
--   vary but should all be in the "small dragon" ballpark)
-- - Visual: dragons aren't tiny dots OR giant whales overlapping the camera
-- - meshScale=4 looks about right for each one
--
-- After running:
-- - If a mesh is wrong size, tweak meshScale in DragonConfig.luau
-- - If a mesh fails to load, the asset ID may be wrong or the asset got
--   moderated away — check Creator Hub > Inventory > Models

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DragonConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("DragonConfig"))

local SPAWN_Y = 80
local SPACING = 25 -- studs between each dragon

print("===== DRAGON MESH VALIDATION =====")

local i = 0
for dragonId, dragon in DragonConfig do
	i += 1
	local x = (i - 3.5) * SPACING -- center the row around x=0
	print(string.format("[%s] assetId=%s scale=%s", dragonId, tostring(dragon.meshAssetId), tostring(dragon.meshScale)))

	if not dragon.meshAssetId then
		warn(`  ⚠ {dragonId}: no meshAssetId set, skipping`)
		continue
	end

	local ok, result = pcall(function()
		return InsertService:LoadAsset(dragon.meshAssetId :: number)
	end)

	if not ok or not result then
		warn(`  ✗ {dragonId}: FAILED to load — {result}`)
		continue
	end

	local container = result :: Model
	-- Find the inner Model the mesh lives in
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

	-- Count parts + measure bounding box
	local partCount = 0
	for _, descendant in (meshContent :: Model):GetDescendants() do
		if descendant:IsA("BasePart") then
			partCount += 1
		end
	end

	if partCount == 0 then
		warn(`  ✗ {dragonId}: mesh loaded but contains 0 BaseParts`)
		container.Parent = nil
		continue
	end

	-- Apply the configured scale and place in workspace
	if meshContent:IsA("Model") then
		(meshContent :: Model):ScaleTo(dragon.meshScale or 1)
		(meshContent :: Model):PivotTo(CFrame.new(x, SPAWN_Y, 0))
		local cf, size = (meshContent :: Model):GetBoundingBox()
		print(string.format("  ✓ %s: %d parts, scaled bbox %.1f×%.1f×%.1f studs", dragonId, partCount, size.X, size.Y, size.Z))
	end

	-- Anchor everything so they don't fall + add a name label
	for _, descendant in (meshContent :: Model):GetDescendants() do
		if descendant:IsA("BasePart") then
			(descendant :: BasePart).Anchored = true
			(descendant :: BasePart).CanCollide = false
		end
	end

	(meshContent :: Model).Name = `Validate_{dragonId}`
	(meshContent :: Model).Parent = workspace

	-- Floating name label so visual check is easy
	local rootPart = (meshContent :: Model).PrimaryPart
		or (meshContent :: Model):FindFirstChildWhichIsA("BasePart", true)
	if rootPart then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(120, 30)
		billboard.StudsOffset = Vector3.new(0, 8, 0)
		billboard.AlwaysOnTop = true
		billboard.Adornee = rootPart
		billboard.Parent = rootPart
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.3
		label.BackgroundColor3 = dragon.color
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Text = dragonId
		label.Parent = billboard
	end

	container.Parent = nil -- discard the LoadAsset wrapper
end

print("===== VALIDATION COMPLETE =====")
print("Visual check: 6 dragons should be in a row at y=" .. SPAWN_Y)
print("If any are wrong size, edit meshScale in DragonConfig.luau")
