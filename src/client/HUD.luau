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
local CONTROLS_KBM = "WASD: Move | Space/Shift: Up/Down | Q: Boost | LMB: Attack | E: Special | R: Shield | B: Menu"
local CONTROLS_GAMEPAD = "L Stick: Move | RB/LB: Up/Down | A: Boost | RT: Attack | LT: Special | X: Shield | Y: Menu"

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
local dragonLevelLabel: TextLabel
local bossCountdownLabel: TextLabel
-- Button-prompt labels in the cooldown panels. Module-level so the live
-- LastInputTypeChanged hook can swap them between KB+M ("LMB"/"E") and
-- gamepad ("RT"/"LT") and touch ("TAP") as the player switches devices.
local breathButtonLabel: TextLabel
local specialButtonLabel: TextLabel
local shieldButtonLabel: TextLabel
-- Boost bar button prompt — sits to the LEFT of the blue boost bar so the
-- kid sees "HOLD Q" or "HOLD A" right next to the meter that drains. Without
-- this label kids couldn't figure out which button made the bar drain.
local boostButtonLabel: TextLabel
-- Shield panel (defensive ability). Same visual style as the Special panel
-- so the kid reads them as a matched pair of action slots.
local shieldCooldownFrame: Frame
local shieldOverlayFrame: Frame -- dark drain overlay during cooldown
local shieldReadyStroke: UIStroke -- pulsing border when shield is ready

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

	-- Boost button prompt — pinned to the LEFT edge of the boost bar so the
	-- kid sees "HOLD Q" / "HOLD A" right next to the meter. Sized to not
	-- overflow the small bar height; the "HOLD" prefix makes it clear this
	-- is a press-and-hold action, not a tap.
	boostButtonLabel = Instance.new("TextLabel")
	boostButtonLabel.Name = "BoostButton"
	boostButtonLabel.Size = UDim2.fromOffset(80, 18)
	-- Position: same row as the boost bar, just to the left of it. The bar
	-- starts at scale-X 0.4; we anchor the label to scale 0.4 with offset
	-- -85 so it sits flush left with a tiny gap.
	boostButtonLabel.Position = UDim2.new(0.4, -85, 0.95, -4)
	boostButtonLabel.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
	boostButtonLabel.BackgroundTransparency = 0.2
	boostButtonLabel.TextColor3 = Color3.fromRGB(120, 200, 255)
	boostButtonLabel.Text = "HOLD Q" -- swapped by LastInputTypeChanged hook
	boostButtonLabel.TextStrokeTransparency = 0
	boostButtonLabel.Font = Enum.Font.GothamBlack
	boostButtonLabel.TextScaled = true
	boostButtonLabel.Parent = screenGui

	local boostBtnCorner = Instance.new("UICorner")
	boostBtnCorner.CornerRadius = UDim.new(0, 4)
	boostBtnCorner.Parent = boostButtonLabel

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

	-- === BOSS COUNTDOWN METER (top center, under round timer) ===
	-- Sprint 10 retention polish: persistent "⚔️ Boss in N rounds" label
	-- so kids passively learn the cadence and have something to play
	-- toward. Tucks under the round timer in the same column. Subdued
	-- grey when far away, gold-pulse when "BOSS ROUND!" Defaults hidden
	-- until the first RoundStart fires with a valid roundsUntilBoss.
	bossCountdownLabel = Instance.new("TextLabel")
	bossCountdownLabel.Name = "BossCountdown"
	bossCountdownLabel.Size = UDim2.fromOffset(220, 22)
	bossCountdownLabel.Position = UDim2.new(0.5, -110, 0, 64)
	bossCountdownLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bossCountdownLabel.BackgroundTransparency = 0.3
	bossCountdownLabel.TextColor3 = Color3.fromRGB(180, 180, 195)
	bossCountdownLabel.Text = "⚔️ Boss in 3 rounds"
	bossCountdownLabel.Font = Enum.Font.GothamBold
	bossCountdownLabel.TextSize = 14
	bossCountdownLabel.Visible = false
	bossCountdownLabel.Parent = screenGui
	local bossCountdownCorner = Instance.new("UICorner")
	bossCountdownCorner.CornerRadius = UDim.new(0, 6)
	bossCountdownCorner.Parent = bossCountdownLabel

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

	-- Sprint 7: dragon level badge (sum of stat upgrade levels for this
	-- dragon). Tucks into the same top-left card next to the dragon name
	-- so the kid's progression is constantly visible during gameplay —
	-- without this, a kid who spent 800 coins on Atk Lv 5 has no in-combat
	-- visual cue that they're stronger (peer audit #2).
	--
	-- POST-PLAYTEST FIX: badge stays visible even at Lv 0 (subdued grey)
	-- so kids can SEE the progression slot exists before they buy. Hiding
	-- it at Lv 0 (initial implementation) made first-time kids ask "where
	-- are the badges?" because the system was invisible until they
	-- interacted with it. The slot now reads "Lv 0" → "Lv 1" → ... so the
	-- placeholder is its own affordance.
	dragonLevelLabel = Instance.new("TextLabel")
	dragonLevelLabel.Name = "DragonLevel"
	dragonLevelLabel.Size = UDim2.fromOffset(70, 28)
	dragonLevelLabel.Position = UDim2.new(0, 264, 0, 16)
	dragonLevelLabel.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	dragonLevelLabel.BackgroundTransparency = 0.3
	dragonLevelLabel.TextColor3 = Color3.fromRGB(170, 170, 180)
	dragonLevelLabel.Text = "Lv 0"
	dragonLevelLabel.Font = Enum.Font.GothamBlack
	dragonLevelLabel.TextSize = 16
	dragonLevelLabel.Visible = true
	dragonLevelLabel.Parent = screenGui
	local levelCorner = Instance.new("UICorner")
	levelCorner.CornerRadius = UDim.new(0, 6)
	levelCorner.Parent = dragonLevelLabel
	local levelStroke = Instance.new("UIStroke")
	levelStroke.Name = "LevelStroke"
	levelStroke.Color = Color3.fromRGB(110, 110, 120)
	levelStroke.Thickness = 1
	levelStroke.Transparency = 0.4
	levelStroke.Parent = dragonLevelLabel

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

	breathButtonLabel = Instance.new("TextLabel")
	breathButtonLabel.Size = UDim2.fromScale(1, 1)
	breathButtonLabel.BackgroundTransparency = 1
	breathButtonLabel.Text = "LMB" -- swapped by LastInputTypeChanged hook below
	breathButtonLabel.TextColor3 = Color3.new(1, 1, 1)
	breathButtonLabel.TextStrokeTransparency = 0
	breathButtonLabel.Font = Enum.Font.GothamBlack
	breathButtonLabel.TextScaled = true
	breathButtonLabel.Parent = breathCooldownFrame

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

	specialButtonLabel = Instance.new("TextLabel")
	specialButtonLabel.Size = UDim2.new(1, 0, 0, 36)
	specialButtonLabel.Position = UDim2.fromOffset(0, 24)
	specialButtonLabel.BackgroundTransparency = 1
	specialButtonLabel.Text = "E / RMB" -- swapped by LastInputTypeChanged hook below
	specialButtonLabel.TextColor3 = Color3.new(1, 1, 1)
	specialButtonLabel.TextStrokeTransparency = 0
	specialButtonLabel.Font = Enum.Font.GothamBlack
	specialButtonLabel.TextScaled = true
	specialButtonLabel.Parent = specialCooldownFrame

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

	-- === SHIELD PANEL (right of Special) ===
	-- Matches the Special panel exactly so the kid reads them as a pair of
	-- action slots. Positioned 150px right of the Special panel so they sit
	-- side-by-side in the bottom-left action area:
	--   [Breath] [Special: NAME / Key / Effect] [Shield: NAME / Key / DEF]
	shieldCooldownFrame = Instance.new("Frame")
	shieldCooldownFrame.Name = "ShieldPanel"
	shieldCooldownFrame.Size = UDim2.fromOffset(140, 90)
	shieldCooldownFrame.Position = UDim2.new(0, 230, 0.88, -25) -- 80 (special left) + 140 (special width) + 10 padding
	shieldCooldownFrame.BackgroundColor3 = Color3.fromRGB(40, 80, 130) -- blue tint = "defensive"
	shieldCooldownFrame.BackgroundTransparency = 0.15
	shieldCooldownFrame.BorderSizePixel = 0
	shieldCooldownFrame.ClipsDescendants = true
	shieldCooldownFrame.Parent = screenGui

	local shieldCornerUI = Instance.new("UICorner")
	shieldCornerUI.CornerRadius = UDim.new(0, 10)
	shieldCornerUI.Parent = shieldCooldownFrame

	shieldReadyStroke = Instance.new("UIStroke")
	shieldReadyStroke.Color = Color3.fromRGB(120, 200, 255)
	shieldReadyStroke.Thickness = 3
	shieldReadyStroke.Transparency = 1
	shieldReadyStroke.Parent = shieldCooldownFrame

	local shieldNameLabel = Instance.new("TextLabel")
	shieldNameLabel.Name = "Name"
	shieldNameLabel.Size = UDim2.new(1, -10, 0, 18)
	shieldNameLabel.Position = UDim2.fromOffset(5, 4)
	shieldNameLabel.BackgroundTransparency = 1
	shieldNameLabel.Text = "SHIELD"
	shieldNameLabel.TextColor3 = Color3.fromRGB(120, 200, 255)
	shieldNameLabel.TextStrokeTransparency = 0
	shieldNameLabel.Font = Enum.Font.GothamBlack
	shieldNameLabel.TextScaled = true
	shieldNameLabel.Parent = shieldCooldownFrame

	shieldButtonLabel = Instance.new("TextLabel")
	shieldButtonLabel.Size = UDim2.new(1, 0, 0, 36)
	shieldButtonLabel.Position = UDim2.fromOffset(0, 24)
	shieldButtonLabel.BackgroundTransparency = 1
	shieldButtonLabel.Text = "R" -- swapped to "X" on gamepad / "TAP" on touch
	shieldButtonLabel.TextColor3 = Color3.new(1, 1, 1)
	shieldButtonLabel.TextStrokeTransparency = 0
	shieldButtonLabel.Font = Enum.Font.GothamBlack
	shieldButtonLabel.TextScaled = true
	shieldButtonLabel.Parent = shieldCooldownFrame

	local shieldEffectLabel = Instance.new("TextLabel")
	shieldEffectLabel.Name = "Effect"
	shieldEffectLabel.Size = UDim2.new(1, -10, 0, 22)
	shieldEffectLabel.Position = UDim2.new(0, 5, 1, -26)
	shieldEffectLabel.BackgroundTransparency = 1
	shieldEffectLabel.Text = "DEF: -80%"
	shieldEffectLabel.TextColor3 = Color3.fromRGB(150, 220, 255)
	shieldEffectLabel.TextStrokeTransparency = 0
	shieldEffectLabel.Font = Enum.Font.GothamBold
	shieldEffectLabel.TextScaled = true
	shieldEffectLabel.Parent = shieldCooldownFrame

	shieldOverlayFrame = Instance.new("Frame")
	shieldOverlayFrame.Name = "CooldownOverlay"
	shieldOverlayFrame.Size = UDim2.fromScale(1, 1)
	shieldOverlayFrame.Position = UDim2.fromScale(0, 0)
	shieldOverlayFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shieldOverlayFrame.BackgroundTransparency = 0.4
	shieldOverlayFrame.BorderSizePixel = 0
	shieldOverlayFrame.ZIndex = 5
	shieldOverlayFrame.Parent = shieldCooldownFrame

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
	-- Per-device labels for the cooldown panels. Same swap pattern as the
	-- bottom controls hint, but applied to the prominent in-screen breath +
	-- special panels so the kid sees "RT" / "LT" on Xbox without needing
	-- to read the small legend at the bottom.
	local function isTouchInput(inputType: Enum.UserInputType): boolean
		return inputType == Enum.UserInputType.Touch
	end
	local function applyDeviceLabels(device: string)
		if breathButtonLabel then
			breathButtonLabel.Text = if device == "gamepad" then "RT"
				elseif device == "touch" then "TAP"
				else "LMB"
		end
		if specialButtonLabel then
			specialButtonLabel.Text = if device == "gamepad" then "LT"
				elseif device == "touch" then "TAP"
				else "E / RMB"
		end
		if shieldButtonLabel then
			shieldButtonLabel.Text = if device == "gamepad" then "X"
				elseif device == "touch" then "TAP"
				else "R"
		end
		if boostButtonLabel then
			boostButtonLabel.Text = if device == "gamepad" then "HOLD A"
				elseif device == "touch" then "HOLD BOOST"
				else "HOLD Q"
		end
	end

	if isGamepadInput(UserInputService:GetLastInputType()) then
		controlsLabel.Text = CONTROLS_GAMEPAD
		applyDeviceLabels("gamepad")
	elseif isTouchInput(UserInputService:GetLastInputType()) then
		applyDeviceLabels("touch")
	end
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		if isGamepadInput(inputType) then
			controlsLabel.Text = CONTROLS_GAMEPAD
			applyDeviceLabels("gamepad")
		elseif inputType == Enum.UserInputType.Keyboard
			or inputType == Enum.UserInputType.MouseMovement
			or inputType == Enum.UserInputType.MouseButton1
			or inputType == Enum.UserInputType.MouseButton2 then
			controlsLabel.Text = CONTROLS_KBM
			applyDeviceLabels("kbm")
		elseif isTouchInput(inputType) then
			applyDeviceLabels("touch")
		end
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
	-- Sprint 7: dragon switched, reset the level badge to subdued "Lv 0"
	-- until the next DragonStatsUpdated for this dragon arrives. Without
	-- this, the old dragon's level lingers on the new dragon's name. The
	-- server fires DragonStatsUpdated immediately after SpawnDragon so
	-- the gap is brief. Stays visible (not hidden) so the slot's affordance
	-- is preserved across switches.
	if dragonLevelLabel then
		dragonLevelLabel.Text = "Lv 0"
		dragonLevelLabel.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
		dragonLevelLabel.TextColor3 = Color3.fromRGB(170, 170, 180)
		local stroke = dragonLevelLabel:FindFirstChild("LevelStroke") :: UIStroke?
		if stroke then stroke.Color = Color3.fromRGB(110, 110, 120) end
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

-- Sprint 10: persistent boss countdown meter under the round timer.
-- Called from init.client.luau when RoundStart fires with the
-- roundsUntilBoss value. 0 = this round IS the boss round (gold pulse
-- "⚔️ BOSS ROUND!"); 1-2 = upcoming (grey "Boss in N rounds").
-- Hidden if roundsUntilBoss is nil (e.g., pre-Sprint-10 server payload
-- shape, or before the first RoundStart of the session lands).
function HUD.setBossCountdown(roundsUntilBoss: number?)
	if not bossCountdownLabel then return end
	if roundsUntilBoss == nil then
		bossCountdownLabel.Visible = false
		return
	end
	bossCountdownLabel.Visible = true
	if roundsUntilBoss <= 0 then
		-- Either current round IS boss round (0) or we're inside the
		-- boss wave already. Mid-round joiners hit this case too —
		-- their first RoundStart fired with 0 because the cadence math
		-- says boss already. Banner becomes "JUMP IN" for that case.
		bossCountdownLabel.Text = "⚔️ BOSS ROUND!"
		bossCountdownLabel.BackgroundColor3 = Color3.fromRGB(80, 30, 20)
		bossCountdownLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	elseif roundsUntilBoss == 1 then
		bossCountdownLabel.Text = "⚔️ Boss next round!"
		bossCountdownLabel.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
		bossCountdownLabel.TextColor3 = Color3.fromRGB(255, 180, 100)
	else
		bossCountdownLabel.Text = `⚔️ Boss in {roundsUntilBoss} rounds`
		bossCountdownLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		bossCountdownLabel.TextColor3 = Color3.fromRGB(180, 180, 195)
	end
end

-- Sprint 7: set the active dragon's total upgrade level (sum of atk + def
-- + spd + special levels, range 0-20). Called from init.client.luau when
-- DragonStatsUpdated arrives for the player's currently-selected dragon.
-- Always visible — at Lv 0 the badge is subdued grey ("placeholder slot");
-- at Lv 1+ it lights up gold so the upgrade is unmissable. POST-PLAYTEST:
-- hiding at Lv 0 caused kids to miss the system entirely.
function HUD.setDragonLevel(totalLevel: number)
	if not dragonLevelLabel then return end
	dragonLevelLabel.Visible = true
	dragonLevelLabel.Text = `Lv {totalLevel}`
	local stroke = dragonLevelLabel:FindFirstChild("LevelStroke") :: UIStroke?
	if totalLevel <= 0 then
		dragonLevelLabel.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
		dragonLevelLabel.TextColor3 = Color3.fromRGB(170, 170, 180)
		if stroke then stroke.Color = Color3.fromRGB(110, 110, 120) end
	else
		-- Gold theme matches the Stat Stone modal's accent. Ramps the
		-- visual signal from "you have a slot here" to "you've invested".
		dragonLevelLabel.BackgroundColor3 = Color3.fromRGB(80, 60, 30)
		dragonLevelLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
		if stroke then stroke.Color = Color3.fromRGB(255, 215, 0) end
	end
end

-- Animation phase for the "ready" pulse. tick()-based so it's frame-rate
-- independent and synchronized across all clients (cosmetic, but consistent).
function HUD.updateCooldowns(breathPct: number, specialPct: number, shieldPct: number?)
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

	-- Same drain + pulse pattern for the Shield panel — matches Special so
	-- the kid reads them as a pair of action slots with consistent feedback.
	if shieldPct and shieldCooldownFrame and shieldOverlayFrame and shieldReadyStroke then
		local drainHeight = 1 - math.clamp(shieldPct, 0, 1)
		shieldOverlayFrame.Size = UDim2.fromScale(1, drainHeight)
		if shieldPct >= 1 then
			local pulse = (math.sin(tick() * math.pi * 2) + 1) * 0.5
			shieldReadyStroke.Transparency = 0.6 - pulse * 0.6
		else
			shieldReadyStroke.Transparency = 1
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

-- ============================================================================
-- SHIELD TUTORIAL POPUP
-- ============================================================================
-- Shows a one-time pointer + callout balloon above the shield panel the FIRST
-- time the local player takes damage. Teachable moment: kid is hurt → sees
-- "PRESS R FOR SHIELD!" → presses R → safe. Better than passive controls
-- text because it's contextually triggered when the kid actually needs it.
--
-- Auto-hides after 5 seconds OR when the kid presses the shield button
-- (whichever comes first). Sticky once-per-session via internal flag.

local shieldTutorialShown = false
local shieldTutorialFrame: Frame? = nil

function HUD.showShieldHint()
	if shieldTutorialShown then return end
	if not shieldCooldownFrame then return end -- HUD not built yet
	shieldTutorialShown = true

	-- Container above the shield panel. AbsolutePosition is in screen pixels
	-- so we read the panel's current spot and float above it. If the layout
	-- shifts (resolution change), the hint is one-shot anyway — fine to be
	-- a snapshot rather than tracking.
	local hint = Instance.new("Frame")
	hint.Name = "ShieldTutorial"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(
		0, shieldCooldownFrame.AbsolutePosition.X + shieldCooldownFrame.AbsoluteSize.X / 2,
		0, shieldCooldownFrame.AbsolutePosition.Y - 12
	)
	hint.Size = UDim2.fromOffset(220, 64)
	hint.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	hint.BackgroundTransparency = 0.05
	hint.BorderSizePixel = 0
	hint.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = hint

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Parent = hint

	-- Big callout text. Device-aware: read whichever shield button label
	-- the HUD currently shows so it always matches what the kid sees.
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	local btn = if shieldButtonLabel and shieldButtonLabel.Text ~= "" then shieldButtonLabel.Text else "R"
	label.Text = `🛡️ Press {btn} for Shield!`
	label.TextColor3 = Color3.fromRGB(20, 30, 60)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = hint

	-- Down-arrow tail pointing at the shield panel below.
	local arrow = Instance.new("Frame")
	arrow.Size = UDim2.fromOffset(16, 16)
	arrow.AnchorPoint = Vector2.new(0.5, 0)
	arrow.Position = UDim2.new(0.5, 0, 1, -8)
	arrow.Rotation = 45
	arrow.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	arrow.BorderSizePixel = 0
	arrow.Parent = hint

	-- Pulse the hint between full and slightly-faded so it draws the eye
	-- even in combat chaos. Period ~0.6s.
	shieldTutorialFrame = hint
	local RunService = game:GetService("RunService")
	local pulseConn: RBXScriptConnection
	pulseConn = RunService.Heartbeat:Connect(function()
		if not hint or not hint.Parent then
			pulseConn:Disconnect()
			return
		end
		local t = (math.sin(tick() * math.pi * 3.3) + 1) * 0.5
		hint.BackgroundTransparency = 0.05 + t * 0.25
	end)

	-- Auto-dismiss after 5 seconds
	task.delay(5, function()
		if hint and hint.Parent then
			hint:Destroy()
			shieldTutorialFrame = nil
		end
	end)
end

-- Called when the kid presses the shield button so the hint dismisses
-- immediately (lesson learned, get out of their way). Idempotent.
function HUD.dismissShieldHint()
	if shieldTutorialFrame and shieldTutorialFrame.Parent then
		shieldTutorialFrame:Destroy()
		shieldTutorialFrame = nil
	end
	shieldTutorialShown = true -- mark seen even if it never rendered
end

-- ============================================================================
-- DEATH OVERLAY
-- ============================================================================
-- Full-screen "YOU DIED" feedback shown when the local player gets KO'd.
-- Without this, kids couldn't tell they died — the camera kept floating, the
-- HUD stayed up, and the only signal was a small "Eliminated! Respawning..."
-- text in the top-center which they didn't notice in combat chaos.
--
-- Components:
--   - Red full-screen tint (40% transparent, fades to 70% over 5s)
--   - Big "YOU DIED" text (gold, scaling down/up a bit for impact)
--   - "Killed by <name>" subtitle so they know who got them
--   - "Respawning in N..." countdown that ticks every second
--   - Auto-clears after `duration` seconds
local deathOverlayGui: ScreenGui? = nil

function HUD.showDeathOverlay(killerName: string, duration: number)
	-- Tear down any prior overlay (rapid-fire deaths possible during a wipe)
	if deathOverlayGui then
		deathOverlayGui:Destroy()
		deathOverlayGui = nil
	end

	-- Build via a non-nullable local first, then assign to the module-level
	-- variable. Without this, Luau parses
	--     deathOverlayGui = Instance.new("ScreenGui")
	--     (deathOverlayGui :: ScreenGui).Name = ...
	-- as a single expression `Instance.new("ScreenGui")(deathOverlayGui :: ScreenGui)`
	-- and throws "ambiguous syntax." A local-then-assign avoids that entirely
	-- and is also cleaner to read.
	local overlay = Instance.new("ScreenGui")
	overlay.Name = "DeathOverlay"
	overlay.ResetOnSpawn = false
	overlay.IgnoreGuiInset = true
	overlay.DisplayOrder = 14 -- above HUD (5) and RoundEndSummary (12)
	overlay.Parent = playerGui
	deathOverlayGui = overlay

	-- Full-screen red tint
	local tint = Instance.new("Frame")
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = Color3.fromRGB(140, 0, 0)
	tint.BackgroundTransparency = 0.6
	tint.BorderSizePixel = 0
	tint.Parent = overlay

	-- Big "YOU DIED" banner — gold on red reads as "this is bad and important"
	local banner = Instance.new("TextLabel")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.4)
	banner.Size = UDim2.fromScale(0.6, 0.18)
	banner.BackgroundTransparency = 1
	banner.Text = "YOU DIED"
	banner.TextColor3 = Color3.fromRGB(255, 215, 0)
	banner.TextStrokeTransparency = 0
	banner.Font = Enum.Font.GothamBlack
	banner.TextScaled = true
	banner.Parent = overlay

	-- Killer name — kids want to know "what got me?"
	local killerLine = Instance.new("TextLabel")
	killerLine.AnchorPoint = Vector2.new(0.5, 0.5)
	killerLine.Position = UDim2.fromScale(0.5, 0.55)
	killerLine.Size = UDim2.fromScale(0.5, 0.06)
	killerLine.BackgroundTransparency = 1
	killerLine.Text = `Killed by {killerName}`
	killerLine.TextColor3 = Color3.fromRGB(255, 200, 200)
	killerLine.TextStrokeTransparency = 0
	killerLine.Font = Enum.Font.GothamBold
	killerLine.TextScaled = true
	killerLine.Parent = overlay

	-- Respawn countdown that ticks every second so kids see time progressing
	local countdown = Instance.new("TextLabel")
	countdown.Name = "Countdown"
	countdown.AnchorPoint = Vector2.new(0.5, 0.5)
	countdown.Position = UDim2.fromScale(0.5, 0.65)
	countdown.Size = UDim2.fromScale(0.4, 0.08)
	countdown.BackgroundTransparency = 1
	countdown.Text = `Respawning in {duration}...`
	countdown.TextColor3 = Color3.new(1, 1, 1)
	countdown.TextStrokeTransparency = 0
	countdown.Font = Enum.Font.GothamBold
	countdown.TextScaled = true
	countdown.Parent = overlay

	-- Tick the countdown text every second
	local generation = (overlay:GetAttribute("Generation") or 0) + 1
	overlay:SetAttribute("Generation", generation)
	task.spawn(function()
		for remaining = duration - 1, 0, -1 do
			task.wait(1)
			-- Bail if a newer overlay replaced us (rapid-respawn edge case)
			if not deathOverlayGui or deathOverlayGui:GetAttribute("Generation") ~= generation then
				return
			end
			if remaining > 0 then
				countdown.Text = `Respawning in {remaining}...`
			else
				countdown.Text = "Respawning..."
			end
		end
	end)

	-- Pulse the YOU DIED banner so it draws the eye even mid-respawn
	task.spawn(function()
		local startTick = tick()
		while deathOverlayGui and deathOverlayGui:GetAttribute("Generation") == generation do
			local elapsed = tick() - startTick
			local pulse = (math.sin(elapsed * math.pi * 2) + 1) * 0.5 -- 0..1
			banner.TextTransparency = pulse * 0.3
			task.wait(0.05)
		end
	end)

	-- Auto-clear after duration
	task.delay(duration, function()
		if deathOverlayGui and deathOverlayGui:GetAttribute("Generation") == generation then
			deathOverlayGui:Destroy()
			deathOverlayGui = nil
		end
	end)
end

return HUD
