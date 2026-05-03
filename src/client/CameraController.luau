--!strict
-- Third-person camera that follows the dragon.
-- Mouse-look for aiming, smooth follow.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraController = {}

local player = Players.LocalPlayer
local camera = game.Workspace.CurrentCamera

local CAMERA_OFFSET = Vector3.new(0, 18, 32) -- higher and further back for aerial combat visibility
local CAMERA_SENSITIVITY = 0.3
local CAMERA_SMOOTHNESS = 0.2

local yaw = 0
local pitch = -25 -- angled down so you see enemies below and ahead
local enabled = false

function CameraController.enable()
	enabled = true
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
end

function CameraController.disable()
	enabled = false
	camera.CameraType = Enum.CameraType.Custom
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

-- Mouse movement for look
UserInputService.InputChanged:Connect(function(input: InputObject)
	if not enabled then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		yaw -= input.Delta.X * CAMERA_SENSITIVITY
		pitch = math.clamp(pitch - input.Delta.Y * CAMERA_SENSITIVITY, -60, 60)
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
	-- Look target is slightly ahead of and below the dragon so you can see enemies in front
	local lookAhead = rootPart.CFrame.LookVector * 10
	local targetPos = dragonPos + lookAhead + Vector3.new(0, -3, 0)

	-- Calculate camera position from yaw/pitch
	local rotation = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
	local offset = rotation:VectorToWorldSpace(CAMERA_OFFSET)
	local cameraPos = dragonPos + offset

	-- Look at the target (slightly ahead of dragon, not at it)
	local targetCF = CFrame.new(cameraPos, targetPos)

	-- Smooth interpolation
	camera.CFrame = camera.CFrame:Lerp(targetCF, CAMERA_SMOOTHNESS)
end)

function CameraController.getLookDirection(): Vector3
	return camera.CFrame.LookVector
end

return CameraController
