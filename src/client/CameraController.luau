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
local CAMERA_OFFSET_NEAR = Vector3.new(0, 4, 8) -- close third-person
local CAMERA_OFFSET_FAR = Vector3.new(0, 18, 32) -- aerial-combat default
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

	-- Compute camera position from yaw/pitch + zoomLevel-driven offset.
	local currentOffset = CAMERA_OFFSET_NEAR:Lerp(CAMERA_OFFSET_FAR, zoomLevel)
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
