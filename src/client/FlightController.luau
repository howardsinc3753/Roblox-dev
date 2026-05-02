--!strict
-- Handles dragon flight input: WASD movement, mouse aiming, boost.
-- Updates BodyVelocity and BodyGyro on the dragon's HumanoidRootPart.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DragonConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("DragonConfig"))

local FlightController = {}

local player = Players.LocalPlayer
local camera = game.Workspace.CurrentCamera

-- Input state
local moveForward = false
local moveBack = false
local moveLeft = false
local moveRight = false
local moveUp = false
local moveDown = false
local boosting = false

-- Boost meter
local boostMeter = 100
local BOOST_MAX = 100
local BOOST_DRAIN = 25 -- per second
local BOOST_RECHARGE = 10 -- per second
local BOOST_MULTIPLIER = 1.8

local currentDragonId = "Ember"
local enabled = false

function FlightController.setDragon(dragonId: string)
	currentDragonId = dragonId
end

function FlightController.enable()
	enabled = true
end

function FlightController.disable()
	enabled = false
end

function FlightController.getBoostPercent(): number
	return boostMeter / BOOST_MAX
end

-- Input bindings
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.W then moveForward = true end
	if input.KeyCode == Enum.KeyCode.S then moveBack = true end
	if input.KeyCode == Enum.KeyCode.A then moveLeft = true end
	if input.KeyCode == Enum.KeyCode.D then moveRight = true end
	if input.KeyCode == Enum.KeyCode.Space then moveUp = true end
	if input.KeyCode == Enum.KeyCode.LeftShift then moveDown = true end
	if input.KeyCode == Enum.KeyCode.Q then boosting = true end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.W then moveForward = false end
	if input.KeyCode == Enum.KeyCode.S then moveBack = false end
	if input.KeyCode == Enum.KeyCode.A then moveLeft = false end
	if input.KeyCode == Enum.KeyCode.D then moveRight = false end
	if input.KeyCode == Enum.KeyCode.Space then moveUp = false end
	if input.KeyCode == Enum.KeyCode.LeftShift then moveDown = false end
	if input.KeyCode == Enum.KeyCode.Q then boosting = false end
end)

-- Main flight update loop
RunService.Heartbeat:Connect(function(dt: number)
	if not enabled then return end

	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local bodyVelocity = rootPart:FindFirstChild("FlightVelocity") :: BodyVelocity?
	local bodyGyro = rootPart:FindFirstChild("FlightGyro") :: BodyGyro?
	if not bodyVelocity or not bodyGyro then return end

	local dragon = DragonConfig[currentDragonId]
	if not dragon then return end

	local baseSpeed = dragon.speed

	-- Boost logic
	local speedMultiplier = 1
	if boosting and boostMeter > 0 then
		speedMultiplier = BOOST_MULTIPLIER
		boostMeter = math.max(0, boostMeter - BOOST_DRAIN * dt)
	else
		boostMeter = math.min(BOOST_MAX, boostMeter + BOOST_RECHARGE * dt)
	end

	local speed = baseSpeed * speedMultiplier

	-- Camera-relative movement
	local camCF = camera.CFrame
	local lookVector = camCF.LookVector
	local rightVector = camCF.RightVector

	local moveDirection = Vector3.zero

	if moveForward then moveDirection += lookVector end
	if moveBack then moveDirection -= lookVector end
	if moveRight then moveDirection += rightVector end
	if moveLeft then moveDirection -= rightVector end
	if moveUp then moveDirection += Vector3.new(0, 1, 0) end
	if moveDown then moveDirection -= Vector3.new(0, 1, 0) end

	if moveDirection.Magnitude > 0 then
		moveDirection = moveDirection.Unit
	end

	bodyVelocity.Velocity = moveDirection * speed

	-- Face the camera direction (yaw only, slight pitch)
	local targetCF = CFrame.new(rootPart.Position, rootPart.Position + lookVector)
	bodyGyro.CFrame = targetCF
end)

return FlightController
