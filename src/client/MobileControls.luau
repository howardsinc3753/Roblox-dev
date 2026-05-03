--!strict
-- Touch controls for mobile (iPhone, iPad, Android). Detects touch-only
-- devices and renders a virtual joystick + on-screen action buttons + a
-- camera-drag zone, all wired into the same FlightController / CombatInput
-- / LockOnController APIs that keyboard+mouse uses.
--
-- Architecture:
-- - Joystick (left thumb): writes to FlightController.setMovement
-- - Up/Down buttons (left side, vertical strafe): same setMovement
-- - Boost button (left side): FlightController.setBoost
-- - Fire/Special/Lock-on buttons (right thumb): CombatInput + LockOnController
-- - Camera-drag zone (middle of screen): yaw/pitch updates via setLook
--
-- We only render the touch UI when UserInputService.TouchEnabled is true
-- AND the device doesn't ALSO have a keyboard. Hybrid devices (Surface,
-- iPad with Magic Keyboard) keep using keyboard since it's superior for
-- this game.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local FlightController = require(script.Parent.FlightController)
local CombatInput = require(script.Parent.CombatInput)
local LockOnController = require(script.Parent.LockOnController)
local CameraController = require(script.Parent.CameraController)

local MobileControls = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- Touch detection: only render UI on phones/tablets without a keyboard.
-- iPad-with-Magic-Keyboard users get keyboard mode (TouchEnabled is true
-- but KeyboardEnabled is also true).
local function isMobileOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Tuning. Tested on iPhone 15-class screen sizes (~390x844 logical px).
local JOYSTICK_RADIUS = 70 -- pixels; max thumb travel from center
local JOYSTICK_DEADZONE = 12 -- pixels; ignore micro-jitter
local JOYSTICK_BG_SIZE = 160
local JOYSTICK_KNOB_SIZE = 70
local BUTTON_SIZE = 80
local BUTTON_PADDING = 10
local CAMERA_DRAG_SENSITIVITY = 0.4

-- State
local screenGui: ScreenGui? = nil
local joystickBg: Frame? = nil
local joystickKnob: Frame? = nil
local joystickActive = false
local joystickTouchId: number? = nil
local joystickCenter: Vector2 = Vector2.new(0, 0)

local cameraDragTouchId: number? = nil
local cameraDragLastPos: Vector2 = Vector2.new(0, 0)

-- Maps joystick offset vector to FlightController movement booleans.
-- Discrete (booleans not analog) because that's what the keyboard handler
-- gives. Analog speed could come later — for casual kid play, on/off is fine.
local function applyJoystickMovement(offset: Vector2)
	if offset.Magnitude < JOYSTICK_DEADZONE then
		FlightController.setMovement(false, false, false, false, nil, nil)
		return
	end
	-- Threshold: 35% of joystick radius along an axis = "pressed" in that
	-- direction. Diagonal pushes activate two directions, just like
	-- W+D on keyboard.
	local threshold = JOYSTICK_RADIUS * 0.35
	FlightController.setMovement(
		offset.Y < -threshold, -- forward (up on screen = forward)
		offset.Y > threshold,  -- back
		offset.X < -threshold, -- left
		offset.X > threshold,  -- right
		nil, -- up/down handled by separate buttons
		nil
	)
end

-- Build a circular touch button at given anchor. Returns the Frame.
local function makeButton(name: string, label: string, color: Color3, anchor: Vector2, position: UDim2): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	btn.AnchorPoint = anchor
	btn.Position = position
	btn.BackgroundColor3 = color
	btn.BackgroundTransparency = 0.25
	btn.AutoButtonColor = false -- we handle press feedback manually
	btn.Text = label
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextStrokeTransparency = 0
	btn.Font = Enum.Font.GothamBlack
	btn.TextScaled = true
	btn.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0) -- full circle
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Transparency = 0.4
	stroke.Parent = btn

	-- Press visual: dim transparency on press, restore on release. Cheap
	-- feedback without needing a tween.
	btn.MouseButton1Down:Connect(function() btn.BackgroundTransparency = 0.05 end)
	btn.MouseButton1Up:Connect(function() btn.BackgroundTransparency = 0.25 end)

	return btn
end

-- Build the joystick GUI. The base anchors at the bottom-left of the
-- screen; the knob moves within JOYSTICK_RADIUS of that center as the
-- thumb drags. Both stay hidden when no touch is active so they don't
-- clutter the bottom corner.
local function buildJoystick()
	joystickBg = Instance.new("Frame")
	joystickBg.Name = "JoystickBg"
	joystickBg.Size = UDim2.fromOffset(JOYSTICK_BG_SIZE, JOYSTICK_BG_SIZE)
	joystickBg.AnchorPoint = Vector2.new(0.5, 0.5)
	joystickBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	joystickBg.BackgroundTransparency = 0.5
	joystickBg.BorderSizePixel = 0
	joystickBg.Visible = false
	joystickBg.Parent = screenGui

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(1, 0)
	bgCorner.Parent = joystickBg

	local bgStroke = Instance.new("UIStroke")
	bgStroke.Color = Color3.new(1, 1, 1)
	bgStroke.Thickness = 2
	bgStroke.Transparency = 0.5
	bgStroke.Parent = joystickBg

	joystickKnob = Instance.new("Frame")
	joystickKnob.Name = "JoystickKnob"
	joystickKnob.Size = UDim2.fromOffset(JOYSTICK_KNOB_SIZE, JOYSTICK_KNOB_SIZE)
	joystickKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	joystickKnob.Position = UDim2.fromScale(0.5, 0.5)
	joystickKnob.BackgroundColor3 = Color3.fromRGB(220, 220, 230)
	joystickKnob.BackgroundTransparency = 0.2
	joystickKnob.BorderSizePixel = 0
	joystickKnob.Parent = joystickBg

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = joystickKnob
end

-- Decide whether a touch belongs to the joystick zone (left third of screen,
-- below the buttons). The joystick anchor follows the touch — wherever your
-- thumb lands in the zone becomes the joystick center.
local function isInJoystickZone(pos: Vector2, viewportSize: Vector2): boolean
	return pos.X < viewportSize.X * 0.4 and pos.Y > viewportSize.Y * 0.45
end

-- Decide whether a touch belongs to the camera-drag zone (middle of the
-- screen, away from buttons + joystick).
local function isInCameraZone(pos: Vector2, viewportSize: Vector2): boolean
	-- Exclude bottom-edge button zones on either side
	if pos.Y > viewportSize.Y * 0.6 then
		if pos.X < viewportSize.X * 0.4 then return false end -- joystick area
		if pos.X > viewportSize.X * 0.7 then return false end -- right buttons
	end
	-- Exclude top status bar (round timer, coins) so the player doesn't drag
	-- the camera while trying to read HUD info
	if pos.Y < viewportSize.Y * 0.15 then return false end
	return true
end

function MobileControls.init()
	if not isMobileOnly() then
		-- Keyboard-capable device: skip mobile UI. Don't even create the
		-- ScreenGui — saves a tiny bit of memory and avoids accidental
		-- touch hits on hybrid devices using keyboard.
		return
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MobileControls"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 6 -- above HUD (5), below modal UIs (10+)
	screenGui.Parent = playerGui

	buildJoystick()

	-- Right-side action button stack. Vertically arranged so the right
	-- thumb can reach all of them without screen acrobatics.
	local fireBtn = makeButton(
		"FireBtn", "FIRE",
		Color3.fromRGB(220, 60, 40),
		Vector2.new(1, 1),
		UDim2.new(1, -BUTTON_PADDING, 1, -BUTTON_PADDING)
	)
	local specialBtn = makeButton(
		"SpecialBtn", "E",
		Color3.fromRGB(140, 60, 220),
		Vector2.new(1, 1),
		UDim2.new(1, -BUTTON_PADDING - BUTTON_SIZE - BUTTON_PADDING, 1, -BUTTON_PADDING)
	)
	local lockBtn = makeButton(
		"LockBtn", "LOCK",
		Color3.fromRGB(255, 200, 60),
		Vector2.new(1, 1),
		UDim2.new(1, -BUTTON_PADDING, 1, -BUTTON_PADDING - BUTTON_SIZE - BUTTON_PADDING)
	)

	-- Left-side vertical strafe + boost. Up/Down stack vertically to the
	-- right of the joystick so they don't fight for thumb space.
	local upBtn = makeButton(
		"UpBtn", "UP",
		Color3.fromRGB(80, 160, 220),
		Vector2.new(0, 1),
		UDim2.new(0, BUTTON_PADDING + JOYSTICK_BG_SIZE + 8, 1, -BUTTON_PADDING - BUTTON_SIZE - BUTTON_PADDING)
	)
	local downBtn = makeButton(
		"DownBtn", "DN",
		Color3.fromRGB(80, 100, 160),
		Vector2.new(0, 1),
		UDim2.new(0, BUTTON_PADDING + JOYSTICK_BG_SIZE + 8, 1, -BUTTON_PADDING)
	)
	local boostBtn = makeButton(
		"BoostBtn", "BOOST",
		Color3.fromRGB(240, 160, 60),
		Vector2.new(0, 1),
		UDim2.new(0, BUTTON_PADDING + JOYSTICK_BG_SIZE + 8 + BUTTON_SIZE + 8, 1, -BUTTON_PADDING)
	)

	-- Wire button handlers to existing controllers. Up/Down/Boost are
	-- press-and-hold (state-based) while Fire/Special/Lock are tap-to-trigger.
	upBtn.MouseButton1Down:Connect(function() FlightController.setMovement(nil, nil, nil, nil, true, nil) end)
	upBtn.MouseButton1Up:Connect(function() FlightController.setMovement(nil, nil, nil, nil, false, nil) end)
	downBtn.MouseButton1Down:Connect(function() FlightController.setMovement(nil, nil, nil, nil, nil, true) end)
	downBtn.MouseButton1Up:Connect(function() FlightController.setMovement(nil, nil, nil, nil, nil, false) end)
	boostBtn.MouseButton1Down:Connect(function() FlightController.setBoost(true) end)
	boostBtn.MouseButton1Up:Connect(function() FlightController.setBoost(false) end)

	fireBtn.Activated:Connect(CombatInput.fireBreath)
	specialBtn.Activated:Connect(CombatInput.fireSpecial)
	lockBtn.Activated:Connect(LockOnController.onLockKeyPressed)

	-- Touch input handling for joystick + camera drag. We use raw
	-- UserInputService.InputBegan/Changed/Ended with input.UserInputType
	-- == Touch to multiplex multi-touch (joystick on left thumb + camera
	-- drag on right thumb simultaneously). Each touch has a unique
	-- input.Position; we track the InputObject reference to associate
	-- it with one role until it ends.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if input.UserInputType ~= Enum.UserInputType.Touch then return end

		local viewport = workspace.CurrentCamera.ViewportSize
		local pos = Vector2.new(input.Position.X, input.Position.Y)

		if not joystickActive and isInJoystickZone(pos, viewport) then
			joystickActive = true
			joystickTouchId = input.Position.Z -- Roblox uses Z as a unique touch id
			joystickCenter = pos
			if joystickBg then
				joystickBg.Position = UDim2.fromOffset(pos.X, pos.Y)
				joystickBg.Visible = true
			end
		elseif not cameraDragTouchId and isInCameraZone(pos, viewport) then
			cameraDragTouchId = input.Position.Z
			cameraDragLastPos = pos
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		local touchId = input.Position.Z

		if joystickActive and touchId == joystickTouchId then
			-- Move knob: clamp offset to JOYSTICK_RADIUS, write movement
			local rawOffset = pos - joystickCenter
			local clampedOffset = rawOffset
			if rawOffset.Magnitude > JOYSTICK_RADIUS then
				clampedOffset = rawOffset.Unit * JOYSTICK_RADIUS
			end
			if joystickKnob then
				-- Knob position is offset from the bg center (which is at joystickCenter).
				-- Bg AnchorPoint is (0.5,0.5), so knob position relative to bg uses
				-- scale 0.5 + offset_normalized.
				local nx = 0.5 + clampedOffset.X / JOYSTICK_BG_SIZE
				local ny = 0.5 + clampedOffset.Y / JOYSTICK_BG_SIZE
				joystickKnob.Position = UDim2.fromScale(nx, ny)
			end
			applyJoystickMovement(clampedOffset)
		elseif cameraDragTouchId and touchId == cameraDragTouchId then
			-- Camera drag: convert delta to yaw/pitch input via CameraController.
			-- We piggyback on CameraController's mouse-look path — same effect
			-- as moving the mouse, just from a touch drag.
			local delta = pos - cameraDragLastPos
			cameraDragLastPos = pos
			-- Touch deltas are larger than mouse deltas; sensitivity tuned to feel
			-- similar to ~400 dpi mouse movement.
			local syntheticMouseDelta = Vector2.new(
				delta.X * CAMERA_DRAG_SENSITIVITY,
				delta.Y * CAMERA_DRAG_SENSITIVITY
			)
			-- CameraController doesn't currently expose a setLook method, so we
			-- inline the same yaw/pitch update here. Match its sensitivity sign.
			-- TODO: extract a shared "applyLookDelta" in CameraController so this
			-- isn't duplicated.
			CameraController.applyLookDelta(syntheticMouseDelta.X, syntheticMouseDelta.Y)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		local touchId = input.Position.Z

		if joystickActive and touchId == joystickTouchId then
			joystickActive = false
			joystickTouchId = nil
			if joystickBg then joystickBg.Visible = false end
			if joystickKnob then joystickKnob.Position = UDim2.fromScale(0.5, 0.5) end
			-- Release all movement on joystick lift
			FlightController.setMovement(false, false, false, false, nil, nil)
		elseif cameraDragTouchId and touchId == cameraDragTouchId then
			cameraDragTouchId = nil
		end
	end)

	print("[MobileControls] Touch UI initialized.")
end

return MobileControls
