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

-- Visual wobble: drives MeshMotor.Transform on the dragon mesh.
-- The body itself stays steady (oriented to camera direction). Only the
-- visible mesh wobbles. Pitch/roll frequencies are slightly offset so they
-- drift in and out of phase — gives a natural figure-8 motion.
local bobTime = 0
local PITCH_AMPLITUDE = math.rad(15)
local PITCH_FREQ = 5 -- rad/s, ~1.25s period
local ROLL_AMPLITUDE = math.rad(10)
local ROLL_FREQ = 3.5 -- rad/s, ~1.8s period

-- Velocity-based body tilt: tilts the dragon BODY (not just visual) so it
-- visibly climbs nose-up, dives nose-down, and banks into turns. This is
-- separate from wobble — it fights the body's "always face camera" rule
-- by adding a velocity-derived offset to the AlignOrientation target.
local PITCH_FROM_VELOCITY = math.rad(30) -- max nose-up/down at full speed
local ROLL_FROM_VELOCITY = math.rad(35) -- max bank angle at full lateral speed

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

function FlightController.isBoosting(): boolean
	return boosting and boostMeter > 0
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

	local linearVelocity = rootPart:FindFirstChild("FlightVelocity") :: LinearVelocity?
	local alignOrientation = rootPart:FindFirstChild("FlightGyro") :: AlignOrientation?
	if not linearVelocity or not alignOrientation then return end

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

	linearVelocity.VectorVelocity = moveDirection * speed

	-- Velocity-based body tilt: nose up when climbing, nose down when diving,
	-- bank left/right when strafing. Reads the actual physics velocity to
	-- ensure the tilt matches what the dragon is *doing*, not what the player
	-- is *pressing* (graceful even when boost meter empties mid-input).
	local velocity = rootPart.AssemblyLinearVelocity
	local maxFlightSpeed = baseSpeed * BOOST_MULTIPLIER
	local pitchFromVel = 0
	local rollFromVel = 0
	if maxFlightSpeed > 0 and velocity.Magnitude > 0.1 then
		pitchFromVel = math.clamp(velocity.Y / maxFlightSpeed, -1, 1) * PITCH_FROM_VELOCITY
		local lateralSpeed = velocity:Dot(rightVector)
		rollFromVel = -math.clamp(lateralSpeed / maxFlightSpeed, -1, 1) * ROLL_FROM_VELOCITY
	end

	-- Body orientation: face camera direction + velocity-based tilt. Wobble
	-- lives on the MeshMotor below, not on the body itself.
	local targetCF = CFrame.new(rootPart.Position, rootPart.Position + lookVector)
		* CFrame.Angles(pitchFromVel, 0, rollFromVel)
	alignOrientation.CFrame = targetCF

	-- Drive the visual wobble via MeshMotor. This rotates only the welded
	-- mesh (via MeshAnchor) — the body stays put, so the camera and breath
	-- aim don't shake. Wobble dampens during boost (stable fast flight).
	bobTime += dt
	local meshMotor = rootPart:FindFirstChild("MeshMotor") :: Motor6D?
	if meshMotor then
		local wobbleScale = if boosting and boostMeter > 0 then 0.4 else 1.0
		local pitchWobble = math.sin(bobTime * PITCH_FREQ) * PITCH_AMPLITUDE * wobbleScale
		local rollWobble = math.cos(bobTime * ROLL_FREQ) * ROLL_AMPLITUDE * wobbleScale
		meshMotor.Transform = CFrame.Angles(pitchWobble, 0, rollWobble)
	end
end)

return FlightController
