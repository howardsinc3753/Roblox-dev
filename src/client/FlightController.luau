--!strict
-- Handles dragon flight input: WASD/keyboard OR PS5/Xbox gamepad, mouse/right-stick
-- aiming, boost. Updates LinearVelocity/AlignOrientation on the dragon's body.
--
-- Gamepad bindings (Xbox names; PS5 equivalents auto-mapped by Roblox):
--   Left Stick (Thumbstick1) → camera-relative move (XZ plane)
--   RB (ButtonR1) → ascend
--   LB (ButtonL1) → descend
--   A  (ButtonA)  → boost (hold)
-- Keyboard bindings stay live in parallel — players using both KB+M AND a
-- gamepad get OR-merged input (last input wins per axis), which is what
-- couch-co-op/console expects.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- ContextActionService runs BEFORE Roblox's default character controller.
-- We need it for ButtonA boost on console because the PlayerModule otherwise
-- consumes ButtonA as the character jump action. UserInputService.InputBegan
-- never fires for ButtonA when a Humanoid is present, even with JumpPower=0.
local ContextActionService = game:GetService("ContextActionService")

local DragonConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("DragonConfig"))

local FlightController = {}

local player = Players.LocalPlayer
local camera = game.Workspace.CurrentCamera

-- Keyboard input state (boolean per direction)
local moveForward = false
local moveBack = false
local moveLeft = false
local moveRight = false
local moveUp = false
local moveDown = false
local boosting = false

-- Gamepad input state. Left stick is analog (Vector2 -1..1), so we store
-- the latest stick value rather than booleans. ButtonR1/L1/A toggle the
-- gamepad-side ascend/descend/boost flags. The heartbeat merges keyboard
-- + gamepad before computing final movement.
local gamepadStick = Vector2.zero
local gamepadAscend = false
local gamepadDescend = false
local gamepadBoost = false
local GAMEPAD_DEADZONE = 0.18 -- thumbstick rest jitter; below this we treat as zero

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

-- Sprint 7: cached upgraded speed per dragon. Populated by
-- applyEffectiveSpeed() when the server fires DragonStatsUpdated. The
-- speed read in the Heartbeat loop prefers this override over
-- DragonConfig.speed so a kid's +Spd upgrades visibly affect movement.
-- Empty until the first server push lands; tickHeartbeat falls back to
-- DragonConfig in that brief window.
local speedOverrides: { [string]: number } = {}

function FlightController.applyEffectiveSpeed(dragonId: string, speed: number)
	speedOverrides[dragonId] = speed
end

function FlightController.setDragon(dragonId: string)
	currentDragonId = dragonId
end

function FlightController.enable()
	enabled = true
end

function FlightController.disable()
	enabled = false
end

-- Sprint 7: explicitly snap the dragon to zero velocity. Just disabling
-- the Heartbeat loop leaves the LinearVelocity constraint at whatever
-- VectorVelocity it had last frame — so a kid moving forward when they
-- opened the upgrade modal keeps drifting forward indefinitely while
-- the modal is open. halt() also zeros the smoothed-velocity cache so
-- mesh wobble stops as if the dragon parked itself. Caller's
-- responsibility to call enable() afterward when input should resume.
function FlightController.halt()
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end
	local linearVelocity = rootPart:FindFirstChild("FlightVelocity") :: LinearVelocity?
	if linearVelocity then
		linearVelocity.VectorVelocity = Vector3.zero
	end
	smoothedVelocity = Vector3.zero
end

function FlightController.getBoostPercent(): number
	return boostMeter / BOOST_MAX
end

function FlightController.isBoosting(): boolean
	return boosting and boostMeter > 0
end

-- Touch-input setters: MobileControls writes to these from its joystick +
-- on-screen buttons. Booleans match the keyboard handlers exactly so the
-- downstream Heartbeat code doesn't need to know whether input came from
-- a keyboard or a touch screen.
function FlightController.setMovement(forward: boolean?, back: boolean?, left: boolean?, right: boolean?, up: boolean?, down: boolean?)
	if forward ~= nil then moveForward = forward end
	if back ~= nil then moveBack = back end
	if left ~= nil then moveLeft = left end
	if right ~= nil then moveRight = right end
	if up ~= nil then moveUp = up end
	if down ~= nil then moveDown = down end
end

function FlightController.setBoost(active: boolean)
	boosting = active
end

-- ============================================================================
-- INPUT BINDINGS — keyboard + gamepad in parallel
-- ============================================================================

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end

	-- Keyboard
	if input.KeyCode == Enum.KeyCode.W then moveForward = true end
	if input.KeyCode == Enum.KeyCode.S then moveBack = true end
	if input.KeyCode == Enum.KeyCode.A then moveLeft = true end
	if input.KeyCode == Enum.KeyCode.D then moveRight = true end
	if input.KeyCode == Enum.KeyCode.Space then moveUp = true end
	if input.KeyCode == Enum.KeyCode.LeftShift then moveDown = true end
	if input.KeyCode == Enum.KeyCode.Q then boosting = true end

	-- Gamepad — Roblox auto-maps Xbox enums to PS5 buttons at runtime.
	-- ButtonA is handled separately via ContextActionService (see below)
	-- because Roblox's PlayerModule consumes it for character jump before
	-- UserInputService.InputBegan ever fires.
	if input.KeyCode == Enum.KeyCode.ButtonR1 then gamepadAscend = true end
	if input.KeyCode == Enum.KeyCode.ButtonL1 then gamepadDescend = true end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.W then moveForward = false end
	if input.KeyCode == Enum.KeyCode.S then moveBack = false end
	if input.KeyCode == Enum.KeyCode.A then moveLeft = false end
	if input.KeyCode == Enum.KeyCode.D then moveRight = false end
	if input.KeyCode == Enum.KeyCode.Space then moveUp = false end
	if input.KeyCode == Enum.KeyCode.LeftShift then moveDown = false end
	if input.KeyCode == Enum.KeyCode.Q then boosting = false end

	if input.KeyCode == Enum.KeyCode.ButtonR1 then gamepadAscend = false end
	if input.KeyCode == Enum.KeyCode.ButtonL1 then gamepadDescend = false end
end)

-- ContextActionService binding for ButtonA boost. CAS fires BEFORE the
-- PlayerModule's character controller, and returning Sink prevents Roblox
-- from also processing it as a jump. We translate the CAS state events
-- (Begin/End/Cancel) to our existing gamepadBoost flag so the rest of the
-- controller doesn't need to know about CAS.
ContextActionService:BindAction(
	"DragonWarz_BoostHold",
	function(_actionName: string, state: Enum.UserInputState, _input: InputObject)
		if state == Enum.UserInputState.Begin then
			gamepadBoost = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			gamepadBoost = false
		end
		-- Sink so Roblox PlayerModule doesn't ALSO interpret ButtonA as jump.
		-- Without this the input would still work (we'd get Begin), but the
		-- character would also try to jump, causing weird physics interactions
		-- with our LinearVelocity-driven flight.
		return Enum.ContextActionResult.Sink
	end,
	false, -- createTouchButton: no, MobileControls renders its own boost button
	Enum.KeyCode.ButtonA
)

-- Thumbstick is reported via InputChanged; we cache the latest Vector2 and
-- read it during the heartbeat. Roblox emits this every time the stick value
-- changes, including when it returns to center.
UserInputService.InputChanged:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		local raw = Vector2.new(input.Position.X, input.Position.Y)
		-- Apply deadzone: tiny stick values from rest jitter become zero.
		-- Beyond the deadzone, rescale so the player gets full -1..1 range.
		local mag = raw.Magnitude
		if mag < GAMEPAD_DEADZONE then
			gamepadStick = Vector2.zero
		else
			local rescaled = (mag - GAMEPAD_DEADZONE) / (1 - GAMEPAD_DEADZONE)
			gamepadStick = raw.Unit * math.min(rescaled, 1)
		end
	end
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

	-- Sprint 7: prefer the upgraded-speed override pushed by the server via
	-- DragonStatsUpdated. Falls back to DragonConfig if no push has landed
	-- (first frame after spawn before the remote arrives, or if the player
	-- hasn't bought any +Spd levels — both yield the base value either way).
	local baseSpeed = speedOverrides[currentDragonId] or dragon.speed

	-- Boost: keyboard Q OR gamepad A (held). Whichever is true wins.
	local effectiveBoost = boosting or gamepadBoost
	local speedMultiplier = 1
	if effectiveBoost and boostMeter > 0 then
		speedMultiplier = BOOST_MULTIPLIER
		boostMeter = math.max(0, boostMeter - BOOST_DRAIN * dt)
	else
		boostMeter = math.min(BOOST_MAX, boostMeter + BOOST_RECHARGE * dt)
	end
	-- Update the canonical `boosting` flag so isBoosting() reads correctly
	-- regardless of input source (camera FOV punch reads this).
	boosting = effectiveBoost

	local speed = baseSpeed * speedMultiplier

	-- Camera-relative movement frame
	local camCF = camera.CFrame
	local lookVector = camCF.LookVector
	local rightVector = camCF.RightVector

	-- Build the XZ-plane move vector by merging keyboard digital + gamepad
	-- analog sources. Keyboard contributes ±1 per axis; gamepad contributes
	-- the analog stick value (-1..1). Where both are pressed, they sum and
	-- get clamped by .Unit normalization below.
	local moveX = 0 -- right (+) / left (-)
	local moveZ = 0 -- forward (+) / back (-)
	if moveForward then moveZ += 1 end
	if moveBack then moveZ -= 1 end
	if moveRight then moveX += 1 end
	if moveLeft then moveX -= 1 end
	-- Gamepad left stick: X = horizontal, Y = vertical (forward is +Y in Roblox)
	moveX += gamepadStick.X
	moveZ += gamepadStick.Y

	-- Vertical: Space/Shift on KB, RB/LB on gamepad. OR-merged.
	local moveY = 0
	if moveUp or gamepadAscend then moveY += 1 end
	if moveDown or gamepadDescend then moveY -= 1 end

	-- Compose into world-space movement. moveX/moveZ are camera-relative,
	-- moveY is always world-vertical so the player can climb regardless of
	-- where they're looking (consistent with arcade flight games).
	local moveDirection = (rightVector * moveX) + (lookVector * moveZ) + Vector3.new(0, moveY, 0)
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
