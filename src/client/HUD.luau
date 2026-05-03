--!strict
-- In-game HUD: health bar, boost meter, coin counter, kill feed,
-- round timer, scoreboard, cooldown indicators.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DragonConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("DragonConfig"))

-- Two control hint strings — swapped at runtime when the player toggles input
-- device. Console text is shorter because TVs sit further back; smaller, denser
-- text becomes unreadable.
local CONTROLS_KBM = "WASD: Move | Space/Shift: Up/Down | Q: Boost | LMB: Attack | E: Special | Y: Open Menu"
local CONTROLS_GAMEPAD = "L Stick: Move | RB/LB: Up/Down | A: Boost | RT: Attack | LT: Special | Y: Menu"

local HUD = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local screenGui: ScreenGui
local healthBar: Frame
local healthFill: Frame
local boostBar: Frame
local boostFill: Frame
local coinLabel: TextLabel
local streakLabel: TextLabel -- "🔥 N" tucked below the coin counter
local roundTimerLabel: TextLabel
local killFeedFrame: Frame
local breathCooldownFrame: Frame
local specialCooldownFrame: Frame
local specialOverlayFrame: Frame -- drains top->bottom as cooldown elapses
local specialNameLabel: TextLabel -- e.g. "FIRE VORTEX"
local specialEffectLabel: TextLabel -- e.g. "DMG: 30" or "HEAL +40"
local specialReadyStroke: UIStroke -- pulsing glow border when ready
local dragonNameLabel: TextLabel

function HUD.create()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DragonWarzHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- === CROSSHAIR (center of screen) ===
	local crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.Size = UDim2.fromOffset(30, 30)
	crosshair.Position = UDim2.new(0.5, -15, 0.5, -15)
	crosshair.BackgroundTransparency = 1
	crosshair.Parent = screenGui

	-- Horizontal line
	local hLine = Instance.new("Frame")
	hLine.Size = UDim2.fromOffset(24, 2)
	hLine.Position = UDim2.new(0.5, -12, 0.5, -1)
	hLine.BackgroundColor3 = Color3.new(1, 1, 1)
	hLine.BackgroundTransparency = 0.2
	hLine.BorderSizePixel = 0
	hLine.Parent = crosshair

	-- Vertical line
	local vLine = Instance.new("Frame")
	vLine.Size = UDim2.fromOffset(2, 24)
	vLine.Position = UDim2.new(0.5, -1, 0.5, -12)
	vLine.BackgroundColor3 = Color3.new(1, 1, 1)
	vLine.BackgroundTransparency = 0.2
	vLine.BorderSizePixel = 0
	vLine.Parent = crosshair

	-- Center dot
	local centerDot = Instance.new("Frame")
	centerDot.Size = UDim2.fromOffset(4, 4)
	centerDot.Position = UDim2.new(0.5, -2, 0.5, -2)
	centerDot.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	centerDot.BorderSizePixel = 0
	centerDot.Parent = crosshair

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = centerDot

	-- === HEALTH BAR (bottom center) ===
	healthBar = Instance.new("Frame")
	healthBar.Name = "HealthBar"
	healthBar.Size = UDim2.new(0.3, 0, 0, 20)
	healthBar.Position = UDim2.new(0.35, 0, 0.92, 0)
	healthBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	healthBar.BorderSizePixel = 0
	healthBar.Parent = screenGui

	local healthCorner = Instance.new("UICorner")
	healthCorner.CornerRadius = UDim.new(0, 6)
	healthCorner.Parent = healthBar

	healthFill = Instance.new("Frame")
	healthFill.Name = "Fill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = healthFill

	local healthText = Instance.new("TextLabel")
	healthText.Name = "Text"
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.BackgroundTransparency = 1
	healthText.Text = "100/100"
	healthText.TextColor3 = Color3.new(1, 1, 1)
	healthText.TextStrokeTransparency = 0
	healthText.Font = Enum.Font.GothamBold
	healthText.TextScaled = true
	healthText.Parent = healthBar

	-- === BOOST BAR (below health) ===
	boostBar = Instance.new("Frame")
	boostBar.Name = "BoostBar"
	boostBar.Size = UDim2.new(0.2, 0, 0, 10)
	boostBar.Position = UDim2.new(0.4, 0, 0.95, 0)
	boostBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	boostBar.BorderSizePixel = 0
	boostBar.Parent = screenGui

	local boostCorner = Instance.new("UICorner")
	boostCorner.CornerRadius = UDim.new(0, 4)
	boostCorner.Parent = boostBar

	boostFill = Instance.new("Frame")
	boostFill.Name = "Fill"
	boostFill.Size = UDim2.fromScale(1, 1)
	boostFill.BackgroundColor3 = Color3.fromRGB(50, 150, 255)
	boostFill.BorderSizePixel = 0
	boostFill.Parent = boostBar

	local boostFillCorner = Instance.new("UICorner")
	boostFillCorner.CornerRadius = UDim.new(0, 4)
	boostFillCorner.Parent = boostFill

	-- === COINS (top right) ===
	coinLabel = Instance.new("TextLabel")
	coinLabel.Name = "Coins"
	coinLabel.Size = UDim2.fromOffset(200, 40)
	coinLabel.Position = UDim2.new(1, -210, 0, 10)
	coinLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	coinLabel.BackgroundTransparency = 0.3
	coinLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	coinLabel.Text = "0 coins"
	coinLabel.Font = Enum.Font.GothamBold
	coinLabel.TextScaled = true
	coinLabel.Parent = screenGui

	local coinCorner = Instance.new("UICorner")
	coinCorner.CornerRadius = UDim.new(0, 8)
	coinCorner.Parent = coinLabel

	-- === STREAK INDICATOR (just under coins) ===
	-- Small "🔥 N" badge so kids see their daily streak at a glance and
	-- feel pressure to not break it. Hidden by default; setStreak shows it.
	streakLabel = Instance.new("TextLabel")
	streakLabel.Name = "Streak"
	streakLabel.Size = UDim2.fromOffset(80, 24)
	streakLabel.Position = UDim2.new(1, -210, 0, 54)
	streakLabel.BackgroundColor3 = Color3.fromRGB(40, 25, 20)
	streakLabel.BackgroundTransparency = 0.3
	streakLabel.TextColor3 = Color3.fromRGB(255, 140, 50)
	streakLabel.Text = "🔥 0"
	streakLabel.Font = Enum.Font.GothamBold
	streakLabel.TextScaled = true
	streakLabel.Visible = false
	streakLabel.Parent = screenGui

	local streakCorner = Instance.new("UICorner")
	streakCorner.CornerRadius = UDim.new(0, 6)
	streakCorner.Parent = streakLabel

	-- === ROUND TIMER (top center) ===
	roundTimerLabel = Instance.new("TextLabel")
	roundTimerLabel.Name = "RoundTimer"
	roundTimerLabel.Size = UDim2.fromOffset(300, 50)
	roundTimerLabel.Position = UDim2.new(0.5, -150, 0, 10)
	roundTimerLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	roundTimerLabel.BackgroundTransparency = 0.3
	roundTimerLabel.TextColor3 = Color3.new(1, 1, 1)
	roundTimerLabel.Text = "Waiting for round..."
	roundTimerLabel.Font = Enum.Font.GothamBold
	roundTimerLabel.TextScaled = true
	roundTimerLabel.Parent = screenGui

	local timerCorner = Instance.new("UICorner")
	timerCorner.CornerRadius = UDim.new(0, 8)
	timerCorner.Parent = roundTimerLabel

	-- === DRAGON NAME (top left) ===
	dragonNameLabel = Instance.new("TextLabel")
	dragonNameLabel.Name = "DragonName"
	dragonNameLabel.Size = UDim2.fromOffset(250, 40)
	dragonNameLabel.Position = UDim2.new(0, 10, 0, 10)
	dragonNameLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	dragonNameLabel.BackgroundTransparency = 0.3
	dragonNameLabel.TextColor3 = Color3.new(1, 1, 1)
	dragonNameLabel.Text = "Ember (Fire)"
	dragonNameLabel.Font = Enum.Font.GothamBold
	dragonNameLabel.TextScaled = true
	dragonNameLabel.Parent = screenGui

	local nameCorner = Instance.new("UICorner")
	nameCorner.CornerRadius = UDim.new(0, 8)
	nameCorner.Parent = dragonNameLabel

	-- === KILL FEED (top right, below coins) ===
	killFeedFrame = Instance.new("Frame")
	killFeedFrame.Name = "KillFeed"
	killFeedFrame.Size = UDim2.fromOffset(300, 200)
	killFeedFrame.Position = UDim2.new(1, -310, 0, 60)
	killFeedFrame.BackgroundTransparency = 1
	killFeedFrame.Parent = screenGui

	local killLayout = Instance.new("UIListLayout")
	killLayout.SortOrder = Enum.SortOrder.LayoutOrder
	killLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	killLayout.Padding = UDim.new(0, 2)
	killLayout.Parent = killFeedFrame

	-- === COOLDOWN INDICATORS (bottom left) ===
	breathCooldownFrame = Instance.new("Frame")
	breathCooldownFrame.Name = "BreathCooldown"
	breathCooldownFrame.Size = UDim2.fromOffset(50, 50)
	breathCooldownFrame.Position = UDim2.new(0, 20, 0.88, 0)
	breathCooldownFrame.BackgroundColor3 = Color3.fromRGB(255, 100, 50)
	breathCooldownFrame.BorderSizePixel = 0
	breathCooldownFrame.Parent = screenGui

	local breathLabel = Instance.new("TextLabel")
	breathLabel.Size = UDim2.fromScale(1, 1)
	breathLabel.BackgroundTransparency = 1
	breathLabel.Text = "LMB"
	breathLabel.TextColor3 = Color3.new(1, 1, 1)
	breathLabel.Font = Enum.Font.GothamBold
	breathLabel.TextScaled = true
	breathLabel.Parent = breathCooldownFrame

	local breathCornerUI = Instance.new("UICorner")
	breathCornerUI.CornerRadius = UDim.new(0, 8)
	breathCornerUI.Parent = breathCooldownFrame

	-- Special panel: prominent so the player notices the cooldown + sees the
	-- damage their special does. Layout:
	--   +-------------------+
	--   |    FIRE VORTEX    | <- specialNameLabel
	--   |        E          | <- big key hint
	--   |     DMG: 30       | <- specialEffectLabel
	--   +-------------------+
	-- A dark overlay drains top->bottom as cooldown elapses. A pulsing glow
	-- stroke appears when the special is ready to cast.
	specialCooldownFrame = Instance.new("Frame")
	specialCooldownFrame.Name = "SpecialPanel"
	specialCooldownFrame.Size = UDim2.fromOffset(140, 90)
	specialCooldownFrame.Position = UDim2.new(0, 80, 0.88, -25)
	specialCooldownFrame.BackgroundColor3 = Color3.fromRGB(60, 30, 120)
	specialCooldownFrame.BackgroundTransparency = 0.15
	specialCooldownFrame.BorderSizePixel = 0
	specialCooldownFrame.ClipsDescendants = true -- so the overlay doesn't escape
	specialCooldownFrame.Parent = screenGui

	local specialCornerUI = Instance.new("UICorner")
	specialCornerUI.CornerRadius = UDim.new(0, 10)
	specialCornerUI.Parent = specialCooldownFrame

	-- Pulsing glow ring around the panel when special is ready. We mutate
	-- its Transparency in updateCooldowns for a "this is castable!" feel.
	specialReadyStroke = Instance.new("UIStroke")
	specialReadyStroke.Color = Color3.fromRGB(255, 215, 80)
	specialReadyStroke.Thickness = 3
	specialReadyStroke.Transparency = 1 -- invisible during cooldown
	specialReadyStroke.Parent = specialCooldownFrame

	specialNameLabel = Instance.new("TextLabel")
	specialNameLabel.Name = "Name"
	specialNameLabel.Size = UDim2.new(1, -10, 0, 18)
	specialNameLabel.Position = UDim2.fromOffset(5, 4)
	specialNameLabel.BackgroundTransparency = 1
	specialNameLabel.Text = "SPECIAL"
	specialNameLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
	specialNameLabel.TextStrokeTransparency = 0
	specialNameLabel.Font = Enum.Font.GothamBlack
	specialNameLabel.TextScaled = true
	specialNameLabel.Parent = specialCooldownFrame

	local specialKeyLabel = Instance.new("TextLabel")
	specialKeyLabel.Size = UDim2.new(1, 0, 0, 36)
	specialKeyLabel.Position = UDim2.fromOffset(0, 24)
	specialKeyLabel.BackgroundTransparency = 1
	specialKeyLabel.Text = "E / RMB"
	specialKeyLabel.TextColor3 = Color3.new(1, 1, 1)
	specialKeyLabel.TextStrokeTransparency = 0
	specialKeyLabel.Font = Enum.Font.GothamBlack
	specialKeyLabel.TextScaled = true
	specialKeyLabel.Parent = specialCooldownFrame

	specialEffectLabel = Instance.new("TextLabel")
	specialEffectLabel.Name = "Effect"
	specialEffectLabel.Size = UDim2.new(1, -10, 0, 22)
	specialEffectLabel.Position = UDim2.new(0, 5, 1, -26)
	specialEffectLabel.BackgroundTransparency = 1
	specialEffectLabel.Text = "DMG: -"
	specialEffectLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	specialEffectLabel.TextStrokeTransparency = 0
	specialEffectLabel.Font = Enum.Font.GothamBold
	specialEffectLabel.TextScaled = true
	specialEffectLabel.Parent = specialCooldownFrame

	-- Dark overlay drains top->bottom over the cooldown duration. Sits on top
	-- of all the text via ZIndex (default = 1, we use 5).
	specialOverlayFrame = Instance.new("Frame")
	specialOverlayFrame.Name = "CooldownOverlay"
	specialOverlayFrame.Size = UDim2.fromScale(1, 1)
	specialOverlayFrame.Position = UDim2.fromScale(0, 0)
	specialOverlayFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	specialOverlayFrame.BackgroundTransparency = 0.4
	specialOverlayFrame.BorderSizePixel = 0
	specialOverlayFrame.ZIndex = 5
	specialOverlayFrame.Parent = specialCooldownFrame

	-- === CONTROLS HINT (bottom center-left) ===
	-- Auto-switches between KB+M and gamepad strings as the player swaps
	-- input devices. Roblox fires LastInputTypeChanged on every input, so
	-- this stays correct in real time without polling.
	local controlsLabel = Instance.new("TextLabel")
	controlsLabel.Name = "Controls"
	-- Wider for console — TV viewing distance + bigger button labels.
	controlsLabel.Size = UDim2.fromOffset(550, 30)
	controlsLabel.Position = UDim2.new(0, 10, 0.98, -5)
	controlsLabel.AnchorPoint = Vector2.new(0, 1)
	controlsLabel.BackgroundTransparency = 1
	controlsLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	controlsLabel.Text = CONTROLS_KBM -- default to KB+M; flips on first gamepad input
	controlsLabel.Font = Enum.Font.Gotham
	controlsLabel.TextScaled = true
	controlsLabel.TextXAlignment = Enum.TextXAlignment.Left
	controlsLabel.Parent = screenGui

	-- Initial check + live updates. Pre-populate based on the type of the
	-- last input Roblox saw before we created the label, then keep it in sync.
	local function isGamepadInput(inputType: Enum.UserInputType): boolean
		return inputType == Enum.UserInputType.Gamepad1
			or inputType == Enum.UserInputType.Gamepad2
			or inputType == Enum.UserInputType.Gamepad3
			or inputType == Enum.UserInputType.Gamepad4
			or inputType == Enum.UserInputType.Gamepad5
			or inputType == Enum.UserInputType.Gamepad6
			or inputType == Enum.UserInputType.Gamepad7
			or inputType == Enum.UserInputType.Gamepad8
	end
	if isGamepadInput(UserInputService:GetLastInputType()) then
		controlsLabel.Text = CONTROLS_GAMEPAD
	end
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		if isGamepadInput(inputType) then
			controlsLabel.Text = CONTROLS_GAMEPAD
		elseif inputType == Enum.UserInputType.Keyboard
			or inputType == Enum.UserInputType.MouseMovement
			or inputType == Enum.UserInputType.MouseButton1
			or inputType == Enum.UserInputType.MouseButton2 then
			controlsLabel.Text = CONTROLS_KBM
		end
		-- Touch is ignored for now (Option D was scoped to console; mobile
		-- support is a separate sprint).
	end)
end

function HUD.updateHealth(current: number, max: number)
	if healthFill then
		healthFill.Size = UDim2.fromScale(math.clamp(current / max, 0, 1), 1)
		-- Color: green > yellow > red
		local pct = current / max
		if pct > 0.5 then
			healthFill.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
		elseif pct > 0.25 then
			healthFill.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
		else
			healthFill.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
		end
	end
	local textLabel = healthBar:FindFirstChild("Text") :: TextLabel?
	if textLabel then
		textLabel.Text = `{math.floor(current)}/{math.floor(max)}`
	end
end

function HUD.updateBoost(percent: number)
	if boostFill then
		boostFill.Size = UDim2.fromScale(math.clamp(percent, 0, 1), 1)
	end
end

function HUD.updateCoins(coins: number)
	if coinLabel then
		coinLabel.Text = `{coins} coins`
	end
end

-- Show / update the streak badge. Pass 0 to hide it (fresh accounts).
function HUD.setStreak(days: number)
	if not streakLabel then return end
	if days <= 0 then
		streakLabel.Visible = false
		return
	end
	streakLabel.Visible = true
	streakLabel.Text = `🔥 {days}`
end

function HUD.updateRoundTimer(text: string)
	if roundTimerLabel then
		roundTimerLabel.Text = text
	end
end

-- Per-element description for the special panel. Damage-dealing specials
-- show "DMG: N", utility specials show their effect ("HEAL +40", etc).
-- Lets the player know what their special actually does at a glance.
local function describeSpecial(dragon: any): string
	local element = dragon.element
	if element == "Fire" then
		return `DMG: {dragon.damage * 2}`
	elseif element == "Lightning" then
		return `DMG: {dragon.damage} x3`
	elseif element == "Ice" then
		return "HEAL +40"
	elseif element == "Earth" then
		return "ARMOR +50"
	elseif element == "Dark" then
		return "INVIS 3s"
	elseif element == "Light" then
		return "HEAL +30 AoE"
	end
	return ""
end

function HUD.setDragon(dragonId: string)
	local dragon = DragonConfig[dragonId]
	if not dragon then return end
	if dragonNameLabel then
		dragonNameLabel.Text = `{dragon.name} ({dragon.element})`
		dragonNameLabel.TextColor3 = dragon.color
	end
	if specialNameLabel then
		specialNameLabel.Text = string.upper(dragon.specialName)
	end
	if specialEffectLabel then
		specialEffectLabel.Text = describeSpecial(dragon)
	end
	-- Tint the special panel to match the dragon's element color (subtle
	-- reminder of which dragon you're flying).
	if specialCooldownFrame then
		specialCooldownFrame.BackgroundColor3 = dragon.secondaryColor
	end
end

-- Animation phase for the "ready" pulse. tick()-based so it's frame-rate
-- independent and synchronized across all clients (cosmetic, but consistent).
function HUD.updateCooldowns(breathPct: number, specialPct: number)
	if breathCooldownFrame then
		breathCooldownFrame.BackgroundTransparency = if breathPct >= 1 then 0 else 0.6
	end

	if specialCooldownFrame and specialOverlayFrame and specialReadyStroke then
		-- specialPct goes 0 -> 1 over the cooldown. We render the overlay
		-- as a "drain": full coverage at pct=0, empty at pct=1. So scale Y
		-- = 1 - pct, anchored to the top.
		local drainHeight = 1 - math.clamp(specialPct, 0, 1)
		specialOverlayFrame.Size = UDim2.fromScale(1, drainHeight)

		if specialPct >= 1 then
			-- Ready: pulse the glow stroke between transparent and opaque.
			-- Period ~1s, amplitude swings between 0 (visible) and 0.6 (faded).
			local pulse = (math.sin(tick() * math.pi * 2) + 1) * 0.5 -- 0..1
			specialReadyStroke.Transparency = 0.6 - pulse * 0.6
		else
			specialReadyStroke.Transparency = 1 -- hidden during cooldown
		end
	end
end

function HUD.addKillFeed(killerName: string, victimName: string)
	if not killFeedFrame then return end

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 20)
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	label.BackgroundTransparency = 0.4
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = `{killerName} eliminated {victimName}`
	label.Font = Enum.Font.Gotham
	label.TextScaled = true
	label.Parent = killFeedFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = label

	-- Fade out and remove after 5 seconds
	task.delay(5, function()
		if label and label.Parent then
			label:Destroy()
		end
	end)
end

return HUD
