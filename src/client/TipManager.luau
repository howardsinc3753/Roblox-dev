--!strict
-- Progressive-disclosure tutorial system. Replaces the all-at-once
-- ControlsOverlay, which kid playtest showed was overwhelming and instantly
-- forgotten. Instead, we show ONE prompt at a time at the bottom-center of
-- the screen, and each prompt auto-dismisses when the kid does the action
-- it's teaching.
--
-- Sequence (basic flight + combat lesson):
--   1. Move        → satisfied by any WASD / Left Stick
--   2. Boost       → satisfied by Q held / ButtonA held
--   3. Fire breath → satisfied by left-click / RT
--   4. Special     → satisfied by E / LT
-- After step 4, the manager goes silent. Shield hint is handled separately
-- by HUD.showShieldHint() on first damage taken — perfect "teachable moment"
-- timing rather than a pre-emptive prompt the kid forgets.
--
-- Visual: large pill at bottom-center with action + button. Slides up on
-- show, slides down + fades on dismiss. Kids actually read these because
-- there's only one and it's tied to right-now context.

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local TipManager = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local DISPLAY_TIMEOUT = 12 -- seconds before a tip auto-advances if the kid hasn't done the action
local SLIDE_DURATION = 0.35

-- Each tip is one teaching moment. `done()` returns true once the player
-- has performed the relevant action — checked every frame in the wait loop.
type Tip = {
	id: string,
	-- Pull the right label for current input device. Done as a function so
	-- a kid swapping from KB to gamepad mid-tutorial gets the right text.
	text: () -> string,
	-- Returns true when the kid has done the action this tip teaches. The
	-- TipManager polls this each frame on the active tip and advances when
	-- it returns true.
	done: () -> boolean,
}

-- Helpers for device-aware label rendering. Touch detection comes first
-- since touch-only devices have neither keyboard nor gamepad.
local function isGamepad(): boolean
	return UserInputService.GamepadEnabled
end
local function isTouchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Per-tip detection state. Each tip closures over a "did the action happen"
-- flag that we set from input listeners.
local moved = false
local boosted = false
local fired = false
local specialed = false

UserInputService.InputBegan:Connect(function(input: InputObject, _gp: boolean)
	if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.A
		or input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.D then
		moved = true
	end
	if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonA then
		boosted = true
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2 then
		fired = true
	end
	if input.KeyCode == Enum.KeyCode.E
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.KeyCode == Enum.KeyCode.ButtonL2 then
		specialed = true
	end
end)

-- Thumbstick movement also counts as "moved" — gamepad players never press W.
UserInputService.InputChanged:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		if input.Position.Magnitude > 0.3 then
			moved = true
		end
	end
end)

local TIPS: { Tip } = {
	{
		id = "move",
		text = function()
			if isGamepad() then return "Push the LEFT STICK to FLY"
			elseif isTouchOnly() then return "Drag the JOYSTICK to FLY"
			else return "Press W A S D to FLY" end
		end,
		done = function() return moved end,
	},
	{
		id = "boost",
		text = function()
			if isGamepad() then return "Hold A to GO FAST"
			elseif isTouchOnly() then return "Tap BOOST to GO FAST"
			else return "Hold Q to GO FAST" end
		end,
		done = function() return boosted end,
	},
	{
		id = "fire",
		text = function()
			if isGamepad() then return "Pull RT to BREATHE FIRE"
			elseif isTouchOnly() then return "Tap FIRE to BREATHE FIRE"
			else return "CLICK to BREATHE FIRE" end
		end,
		done = function() return fired end,
	},
	{
		id = "special",
		text = function()
			if isGamepad() then return "Pull LT for your SPECIAL"
			elseif isTouchOnly() then return "Tap E for your SPECIAL"
			else return "Press E for your SPECIAL" end
		end,
		done = function() return specialed end,
	},
}

local screenGui: ScreenGui? = nil
local pill: Frame? = nil
local pillLabel: TextLabel? = nil
local sequenceStarted = false

local function buildPill()
	local sg = Instance.new("ScreenGui")
	sg.Name = "TipManager"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 7 -- above HUD, below modals
	sg.Parent = playerGui
	screenGui = sg

	local p = Instance.new("Frame")
	p.Name = "Pill"
	p.AnchorPoint = Vector2.new(0.5, 1)
	-- Sits well above the cooldown panels so it doesn't compete with the
	-- shield/special UI for attention. ~75% down the screen.
	p.Position = UDim2.new(0.5, 0, 0.78, 0)
	p.Size = UDim2.fromOffset(440, 56)
	p.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
	p.BackgroundTransparency = 0.05
	p.BorderSizePixel = 0
	p.Visible = false
	p.Parent = sg
	pill = p

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = p

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 215, 0)
	stroke.Thickness = 3
	stroke.Parent = p

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -30, 1, -10)
	lbl.Position = UDim2.fromOffset(15, 5)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(255, 255, 200)
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.Text = ""
	lbl.Parent = p
	pillLabel = lbl
end

-- Slide-in from below + fade in. Slides out + fades on dismiss.
local function showPill(text: string)
	if not pill or not pillLabel then return end
	pillLabel.Text = text
	pill.Visible = true
	pill.Position = UDim2.new(0.5, 0, 1, 80) -- start below screen
	pill.BackgroundTransparency = 1

	TweenService:Create(pill, TweenInfo.new(SLIDE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.78, 0),
		BackgroundTransparency = 0.05,
	}):Play()
end

local function hidePill(onComplete: () -> ())
	if not pill then onComplete(); return end
	local tween = TweenService:Create(pill, TweenInfo.new(SLIDE_DURATION * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, 1, 80),
		BackgroundTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		if pill then pill.Visible = false end
		onComplete()
	end)
end

-- Walk the tip list once. Each tip shows, then we wait until either the
-- kid does the action OR the timeout elapses, then advance to the next.
function TipManager.startSequence()
	if sequenceStarted then return end
	sequenceStarted = true
	if not screenGui then buildPill() end

	task.spawn(function()
		-- Brief delay on first spawn so the dragon settles + the kid can
		-- orient before we throw a prompt at them.
		task.wait(1.5)

		for _, tip in TIPS do
			-- If the kid already did this action before we got here (e.g.,
			-- pre-tutorial movement during spawn animation), skip it.
			if tip.done() then continue end

			showPill(tip.text())

			-- Refresh the text every 0.5s in case the kid swaps device
			-- mid-tip (controller plug-in mid-tutorial).
			local startTick = tick()
			local lastDeviceCheck = tick()
			while not tip.done() and (tick() - startTick) < DISPLAY_TIMEOUT do
				if tick() - lastDeviceCheck > 0.5 then
					lastDeviceCheck = tick()
					if pillLabel then pillLabel.Text = tip.text() end
				end
				task.wait(0.05)
			end

			-- Brief "good job" hold on success vs silent dismiss on timeout.
			-- A tiny pause lets the kid feel the "I did it!" beat instead of
			-- the next prompt instantly replacing the current one.
			if tip.done() and pillLabel then
				pillLabel.Text = "✓ " .. tip.text()
				if pill then pill.BackgroundColor3 = Color3.fromRGB(40, 80, 40) end
				task.wait(0.6)
				if pill then pill.BackgroundColor3 = Color3.fromRGB(20, 30, 50) end
			end

			-- Hide between tips, then briefly pause before the next slides
			-- in. Without this beat the prompts feel like a rapid-fire quiz.
			local doneFlag = false
			hidePill(function() doneFlag = true end)
			while not doneFlag do task.wait(0.05) end
			task.wait(0.3)
		end

		-- Tutorial complete. Manager goes silent forever. Shield hint
		-- continues to fire from HUD.showShieldHint() on first damage.
	end)
end

-- Manual dismiss in case we ever need it (e.g., pause menu opens). Currently
-- unused but cheap to keep wired.
function TipManager.dismissAll()
	if pill then
		pill.Visible = false
	end
end

return TipManager
