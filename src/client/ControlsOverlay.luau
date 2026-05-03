--!strict
-- First-Time User Experience (FTUE) controls card.
--
-- Shows a big, easy-to-read controls reference on first spawn so kids know
-- what every button does — especially on console where the persistent
-- bottom-of-screen hint is too small to read from a couch.
--
-- Behavior:
-- - Renders ONCE per session on first spawn (won't re-show on respawn)
-- - Auto-dismisses after DISPLAY_DURATION seconds OR after the player
--   makes their first kill — whichever comes first
-- - Auto-detects whether the player is on gamepad, KB+M, or touch and
--   shows the right button labels for their device
-- - Updates labels live if the player swaps devices (picks up controller
--   mid-session, etc.)
-- - Background is dim but click-through so the player can still play
--   while reading

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local ControlsOverlay = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local DISPLAY_DURATION = 12 -- seconds visible before auto-dismiss
local FADE_OUT = 0.6 -- seconds of fade-out animation

local screenGui: ScreenGui? = nil
local card: Frame? = nil
local shownThisSession = false
local dismissed = false

-- Each control row maps action → device-specific labels. Renders as a
-- two-column table: ACTION (left) | BUTTONS (right). Button strings are
-- hand-tuned for kid-readability — "Speed Up" instead of "Boost", etc.
type ControlRow = { action: string, kbm: string, gamepad: string, touch: string }

local CONTROLS: { ControlRow } = {
	{ action = "Move",         kbm = "WASD",         gamepad = "Left Stick",       touch = "Joystick (left)" },
	{ action = "Look / Aim",   kbm = "Mouse",        gamepad = "Right Stick",      touch = "Drag (right)" },
	{ action = "Fly Up",       kbm = "Space",        gamepad = "RB",               touch = "UP button" },
	{ action = "Fly Down",     kbm = "Shift",        gamepad = "LB",               touch = "DOWN button" },
	{ action = "Speed Up",     kbm = "Q",            gamepad = "A",                touch = "BOOST button" },
	{ action = "Breath Attack", kbm = "Left Click",  gamepad = "RT",               touch = "FIRE button" },
	{ action = "Special Power", kbm = "E",           gamepad = "LT",               touch = "E button" },
	{ action = "Shield (Defense)", kbm = "R",        gamepad = "X",                touch = "SHIELD button" },
	{ action = "Lock Target",  kbm = "F",            gamepad = "Click Right Stick", touch = "LOCK button" },
	{ action = "Open Menu",    kbm = "B",            gamepad = "Y",                touch = "MENU button" },
}

-- Detect the right device. Touch is checked FIRST because mobile-only
-- devices have neither keyboard nor gamepad; gamepad is checked NEXT
-- because the LastInputType swap will reflect that the kid is using a
-- controller. Falls back to KB+M as the default.
local function currentDevice(): string
	-- Gamepad takes priority if connected — most relevant for console kids
	if UserInputService.GamepadEnabled then
		return "gamepad"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	end
	return "kbm"
end

-- Pull the right column for the current device, with a friendly column header
local function labelFor(row: ControlRow, device: string): string
	if device == "gamepad" then return row.gamepad
	elseif device == "touch" then return row.touch
	else return row.kbm end
end

local function deviceTitle(device: string): string
	if device == "gamepad" then return "GAMEPAD CONTROLS"
	elseif device == "touch" then return "TOUCH CONTROLS"
	else return "KEYBOARD + MOUSE CONTROLS" end
end

-- Build the card visual. Called once on first show; subsequent re-renders
-- (e.g., the player swaps from KB to gamepad) just update the label texts.
local function buildCard()
	-- Use concrete-typed locals so we can dot-access without strict-mode casts.
	-- Critical: starting a new statement with `(...).foo` after an assignment
	-- is parsed by Lua as a function call on the previous line's result, which
	-- crashed the script at module load. Concrete locals dodge the ambiguity.
	local sg: ScreenGui = Instance.new("ScreenGui")
	sg.Name = "ControlsOverlay"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 12 -- above HUD, below modals like DragonSelect
	sg.Parent = playerGui
	screenGui = sg

	-- Click-through: dim backdrop is purely visual, doesn't eat input.
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.55
	backdrop.BorderSizePixel = 0
	backdrop.Active = false -- click-through
	backdrop.Parent = sg

	-- Center card. Sized large enough to read from a TV at couch distance
	-- (Xbox/PS5 kid is the worst-case viewing distance).
	local c: Frame = Instance.new("Frame")
	c.Name = "Card"
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = UDim2.fromScale(0.5, 0.5)
	c.Size = UDim2.fromOffset(620, 580) -- bumped 540→580 to fit the new Shield row
	c.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
	c.BackgroundTransparency = 0.05
	c.BorderSizePixel = 0
	c.Parent = sg
	card = c

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 215, 0)
	stroke.Thickness = 4
	stroke.Parent = card

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 0, 50)
	title.Position = UDim2.fromOffset(20, 16)
	title.BackgroundTransparency = 1
	title.Text = deviceTitle(currentDevice())
	title.TextColor3 = Color3.fromRGB(255, 215, 0)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.Parent = card

	-- Subtitle hint
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -40, 0, 22)
	subtitle.Position = UDim2.fromOffset(20, 70)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Auto-closes in a few seconds — start playing whenever"
	subtitle.TextColor3 = Color3.fromRGB(180, 180, 200)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextScaled = true
	subtitle.Parent = card

	-- Controls list — tall, easy-to-read rows. Built as Frames so we can
	-- update the right-column text live when device changes.
	local list = Instance.new("Frame")
	list.Name = "List"
	list.Size = UDim2.new(1, -40, 1, -130)
	list.Position = UDim2.fromOffset(20, 100)
	list.BackgroundTransparency = 1
	list.Parent = card

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = list

	local device = currentDevice()
	for i, row in CONTROLS do
		local rowFrame = Instance.new("Frame")
		rowFrame.Name = `Row_{i}`
		rowFrame.Size = UDim2.new(1, 0, 0, 36)
		rowFrame.BackgroundColor3 = if i % 2 == 0
			then Color3.fromRGB(30, 32, 44) else Color3.fromRGB(36, 38, 52)
		rowFrame.BackgroundTransparency = 0.2
		rowFrame.BorderSizePixel = 0
		rowFrame.LayoutOrder = i
		rowFrame.Parent = list

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent = rowFrame

		-- Action name (left side, ~45% width)
		local actionLabel = Instance.new("TextLabel")
		actionLabel.Name = "Action"
		actionLabel.Size = UDim2.new(0.5, -10, 1, -8)
		actionLabel.Position = UDim2.fromOffset(12, 4)
		actionLabel.BackgroundTransparency = 1
		actionLabel.Text = row.action
		actionLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
		actionLabel.Font = Enum.Font.GothamMedium
		actionLabel.TextScaled = true
		actionLabel.TextXAlignment = Enum.TextXAlignment.Left
		actionLabel.Parent = rowFrame

		-- Button label (right side, ~50% width). This is the part that
		-- updates if the device swaps — named "Button" so we can find it.
		local buttonLabel = Instance.new("TextLabel")
		buttonLabel.Name = "Button"
		buttonLabel.Size = UDim2.new(0.5, -10, 1, -8)
		buttonLabel.Position = UDim2.new(0.5, 0, 0, 4)
		buttonLabel.BackgroundTransparency = 1
		buttonLabel.Text = labelFor(row, device)
		buttonLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
		buttonLabel.Font = Enum.Font.GothamBold
		buttonLabel.TextScaled = true
		buttonLabel.TextXAlignment = Enum.TextXAlignment.Right
		buttonLabel.Parent = rowFrame
	end
end

-- Re-render only the right-column button labels when the player swaps
-- input device (e.g., grabs a controller mid-session). Cheaper than
-- destroying and rebuilding the whole card.
local function refreshLabelsForDevice()
	if not card then return end
	local list = card:FindFirstChild("List") :: Frame?
	if not list then return end
	local title = card:FindFirstChild("Title") :: TextLabel?

	local device = currentDevice()
	if title then title.Text = deviceTitle(device) end

	for i, row in CONTROLS do
		local rowFrame = list:FindFirstChild(`Row_{i}`) :: Frame?
		if rowFrame then
			local buttonLabel = rowFrame:FindFirstChild("Button") :: TextLabel?
			if buttonLabel then
				buttonLabel.Text = labelFor(row, device)
			end
		end
	end
end

-- Public API: call once on first spawn. Subsequent calls are no-ops.
function ControlsOverlay.show()
	if shownThisSession then return end
	shownThisSession = true

	buildCard()

	-- Slide-in from above the screen for a tiny bit of polish.
	-- Local concrete-typed binding to dodge the Lua "(...)" ambiguous-call
	-- parser issue (a paren-prefixed line after assignment is parsed as a
	-- function call on the previous line's result).
	local cardRef = card
	if cardRef then
		cardRef.Position = UDim2.fromScale(0.5, -0.5)
		local slideIn = TweenService:Create(cardRef, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.5),
		})
		slideIn:Play()
	end

	-- Auto-dismiss after DISPLAY_DURATION
	task.delay(DISPLAY_DURATION, function()
		ControlsOverlay.dismiss()
	end)

	-- Keep labels current if the player swaps device while the card is up
	UserInputService.LastInputTypeChanged:Connect(function()
		refreshLabelsForDevice()
	end)
end

-- Dismiss early — called by the auto-timer OR by init.client when the
-- player gets their first kill (whichever happens first).
function ControlsOverlay.dismiss()
	if dismissed then return end
	dismissed = true
	local cardRef = card
	local sgRef = screenGui
	if not cardRef or not sgRef then return end

	local fadeOut = TweenService:Create(cardRef, TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromScale(0.5, -0.5),
		BackgroundTransparency = 1,
	})
	fadeOut:Play()
	fadeOut.Completed:Connect(function()
		if sgRef then
			sgRef:Destroy()
			screenGui = nil
			card = nil
		end
	end)
end

return ControlsOverlay
