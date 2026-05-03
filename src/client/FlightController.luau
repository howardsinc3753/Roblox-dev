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

-- Visual wobble: drives MeshMotor.Transform on EVERY player's dragon, not
-- just the local one. Motor6D.Transform set from a LocalScript only replicates
-- when the writer has network ownership, so the local client must drive every
-- visible dragon's wobble itself. Uses tick() for phase coherence — every
-- client computes the same wobble for the same dragon at the same time.
local PITCH_AMPLITUDE = math.rad(15)
local PITCH_FREQ = 5 -- rad/s, ~1.25s period
local ROLL_AMPLITUDE = math.rad(10)
local ROLL_FREQ = 3.5 -- rad/s, ~1.8s period

-- Velocity-based body tilt: tilts the dragon BODY (not just visual) so it
-- visibly climbs nose-up, dives nose-down, and banks into turns.
local PITCH_FROM_VELOCITY = math.rad(30) -- max nose-up/down at full speed
local ROLL_FROM_VELOCITY = math.rad(35) -- max bank angle at full lateral speed
local VELOCITY_SMOOTH_RATE = 8 -- per second; smooths physics jitter from raw velocity

-- Smoothed velocity for tilt. Raw AssemblyLinearVelocity has small physics
-- fluctuations from constraint resolution that flicker the body tilt visibly.
local smoothedVelocity = Vector3.zero

-- Wobble phase accumulator. Drives the sin/cos oscillations on MeshMotor.
-- Persists across frames so the wobble is continuous regardless of frame rate.
local bobTime = 0

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

	-- Smooth the raw physics velocity to kill constraint-jitter on tilt.
	-- Frame-rate-independent: 1 - exp(-rate*dt) is the canonical alpha for
	-- exponential smoothing.
	local rawVelocity = rootPart.AssemblyLinearVelocity
	local smoothAlpha = 1 - math.exp(-VELOCITY_SMOOTH_RATE * dt)
	smoothedVelocity = smoothedVelocity:Lerp(rawVelocity, smoothAlpha)

	-- Velocity-based body tilt: nose up when climbing, nose down when diving,
	-- bank left/right when strafing. Reads smoothed physics velocity so the
	-- tilt matches what the dragon is *doing*, not what the player is
	-- *pressing* (graceful even when boost meter empties mid-input).
	local maxFlightSpeed = baseSpeed * BOOST_MULTIPLIER
	local pitchFromVel = 0
	local rollFromVel = 0
	if maxFlightSpeed > 0 and smoothedVelocity.Magnitude > 0.1 then
		pitchFromVel = math.clamp(smoothedVelocity.Y / maxFlightSpeed, -1, 1) * PITCH_FROM_VELOCITY
		local lateralSpeed = smoothedVelocity:Dot(rightVector)
		rollFromVel = -math.clamp(lateralSpeed / maxFlightSpeed, -1, 1) * ROLL_FROM_VELOCITY
	end

	-- Body orientation: face camera direction + velocity-based tilt. Wobble
	-- is driven separately (in the wobble loop below) for ALL players' dragons.
	local targetCF = CFrame.new(rootPart.Position, rootPart.Position + lookVector)
		* CFrame.Angles(pitchFromVel, 0, rollFromVel)
	alignOrientation.CFrame = targetCF
end)

-- Wobble loop: drives Motor6D.Transform on every player's dragon mesh.
-- Runs unconditionally (not gated by `enabled`) — other dragons should keep
-- wobbling visually even when the local player is dead or has controls
-- disabled. tick() is approximately sync'd across clients, so wobble phase
-- is coherent (every client sees the same wobble at the same time).
RunService.Heartbeat:Connect(function(_dt: number)
	local sharedTime = tick()
	local pitchWobble = math.sin(sharedTime * PITCH_FREQ) * PITCH_AMPLITUDE
	local rollWobble = math.cos(sharedTime * ROLL_FREQ) * ROLL_AMPLITUDE
	local wobbleTransform = CFrame.Angles(pitchWobble, 0, rollWobble)

	for _, p in Players:GetPlayers() do
		local char = p.Character
		if not char then continue end
		local rp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rp then continue end
		local motor = rp:FindFirstChild("MeshMotor") :: Motor6D?
		if motor then
			motor.Transform = wobbleTransform
		end
	end
end)

return FlightController
