--!strict
-- Third-person camera that follows the dragon.
-- Mouse-look for aiming, mouse wheel for zoom, FOV punch on boost.
-- Camera direction is mouse-driven (yaw/pitch), independent of the dragon's
-- body orientation — so velocity-tilt and wobble on the body do NOT shake
-- the camera or affect aim.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local FlightController = require(script.Parent.FlightController)

local CameraController = {}

local player = Players.LocalPlayer
local camera = game.Workspace.CurrentCamera

-- Zoom: lerps between near and far CAMERA_OFFSET based on mouse wheel.
-- At zoomLevel < FIRST_PERSON_THRESHOLD, switches to first-person (camera
-- inside dragon's head, local mesh hidden).
local FIRST_PERSON_OFFSET = Vector3.new(0, 1, -3) -- inside dragon's head, looking forward
local CAMERA_OFFSET_NEAR = Vector3.new(0, 4, 8) -- close third-person (zoomLevel just past first-person)
local CAMERA_OFFSET_FAR = Vector3.new(0, 18, 32) -- aerial-combat default
local FIRST_PERSON_THRESHOLD = 0.05 -- below this, snap to first-person
local CAMERA_SENSITIVITY = 0.3
local CAMERA_SMOOTH_RATE = 12 -- per second; ~0.2 alpha at 60fps, frame-rate independent
local ZOOM_SENSITIVITY = 0.1

-- FOV punch: lerps to BOOST FOV while boosting, back to DEFAULT when not.
local FOV_DEFAULT = 70
local FOV_BOOST = 85
local FOV_LERP_RATE = 6 -- per second; alpha = 1 - exp(-rate*dt)

local yaw = 0
local pitch = -25 -- angled down so you see enemies below and ahead
local zoomLevel = 1.0 -- 0 = nearest, 1 = furthest
local enabled = false
local wasFirstPerson = false -- tracks state to avoid setting transparency every frame

-- Hide/show the local player's dragon mesh. Used for first-person mode so
-- the player sees through the dragon's eyes without their own model blocking.
-- LocalTransparencyModifier only affects the local view, so other clients
-- still see this player's dragon normally.
local function setLocalMeshVisible(character: Model?, visible: boolean)
	if not character then return end
	local modifier = if visible then 0 else 1
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			(descendant :: BasePart).LocalTransparencyModifier = modifier
		elseif descendant:IsA("BillboardGui") then
			(descendant :: BillboardGui).Enabled = visible
		end
	end
end

function CameraController.enable()
	enabled = true
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV_DEFAULT
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
end

function CameraController.disable()
	enabled = false
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = FOV_DEFAULT
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	-- Restore mesh visibility so a respawn or spectator view shows the dragon
	setLocalMeshVisible(player.Character, true)
	wasFirstPerson = false
end

-- Mouse movement = look. Mouse wheel = zoom.
UserInputService.InputChanged:Connect(function(input: InputObject)
	if not enabled then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		yaw -= input.Delta.X * CAMERA_SENSITIVITY
		pitch = math.clamp(pitch - input.Delta.Y * CAMERA_SENSITIVITY, -60, 60)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		-- input.Position.Z is +1 (scroll up = zoom in) or -1 (scroll down = zoom out)
		zoomLevel = math.clamp(zoomLevel - input.Position.Z * ZOOM_SENSITIVITY, 0, 1)
	end
end)

-- Camera update
RunService.RenderStepped:Connect(function(dt: number)
	if not enabled then return end

	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local dragonPos = rootPart.Position
	local isFirstPerson = zoomLevel < FIRST_PERSON_THRESHOLD

	-- Toggle local mesh visibility on first-person state changes only (not
	-- every frame; setting LocalTransparencyModifier is cheap but pointless
	-- to do redundantly).
	if isFirstPerson ~= wasFirstPerson then
		setLocalMeshVisible(character, not isFirstPerson)
		wasFirstPerson = isFirstPerson
	end

	-- Compute camera position from yaw/pitch + zoomLevel-driven offset.
	-- First-person uses fixed FIRST_PERSON_OFFSET so the camera sits in the
	-- dragon's head consistently regardless of zoomLevel rounding.
	local currentOffset = if isFirstPerson
		then FIRST_PERSON_OFFSET
		else CAMERA_OFFSET_NEAR:Lerp(CAMERA_OFFSET_FAR, zoomLevel)
	local rotation = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
	local offset = rotation:VectorToWorldSpace(currentOffset)
	local cameraPos = dragonPos + offset

	-- Look ahead in the CAMERA's forward direction (mouse-driven), NOT the
	-- dragon body's LookVector. This is the critical decoupling — it stops
	-- body wobble/tilt from shaking the camera target.
	local cameraForward = rotation:VectorToWorldSpace(Vector3.new(0, 0, -1))
	local targetPos = dragonPos + cameraForward * 10

	-- Camera smoothness: 1 - exp(-rate*dt) is the canonical frame-rate
	-- independent exponential lerp. Previously used a fixed 0.2 alpha which
	-- made the camera feel twice as laggy at 30fps as at 60fps.
	local targetCF = CFrame.new(cameraPos, targetPos)
	local cameraSmooth = 1 - math.exp(-CAMERA_SMOOTH_RATE * dt)
	camera.CFrame = camera.CFrame:Lerp(targetCF, cameraSmooth)

	-- FOV punch when boosting. Same exp form as camera smoothing for
	-- consistency and accuracy at low framerates.
	local targetFOV = if FlightController.isBoosting() then FOV_BOOST else FOV_DEFAULT
	local fovLerp = 1 - math.exp(-FOV_LERP_RATE * dt)
	camera.FieldOfView += (targetFOV - camera.FieldOfView) * fovLerp
end)

function CameraController.getLookDirection(): Vector3
	return camera.CFrame.LookVector
end

return CameraController
