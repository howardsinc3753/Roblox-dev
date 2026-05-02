--!strict
-- Third-person camera that follows the dragon.
-- Mouse-look for aiming, smooth follow.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraController = {}

local player = Players.LocalPlayer
local camera = game.Workspace.CurrentCamera

local CAMERA_OFFSET = Vector3.new(0, 8, 20) -- behind and above
local CAMERA_SENSITIVITY = 0.3
local CAMERA_SMOOTHNESS = 0.15

local yaw = 0
local pitch = -10 -- slight downward angle
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

	local targetPos = rootPart.Position

	-- Calculate camera position from yaw/pitch
	local rotation = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
	local offset = rotation:VectorToWorldSpace(CAMERA_OFFSET)
	local cameraPos = targetPos + offset

	-- Look at the target
	local targetCF = CFrame.new(cameraPos, targetPos)

	-- Smooth interpolation
	camera.CFrame = camera.CFrame:Lerp(targetCF, CAMERA_SMOOTHNESS)
end)

function CameraController.getLookDirection(): Vector3
	return camera.CFrame.LookVector
end

return CameraController
