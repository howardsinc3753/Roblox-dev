--!strict
-- Welcome Banner: shown once per session when the player first joins.
-- Displays their daily login bonus, streak count + progress to max streak,
-- and teases the first-win-of-day bonus if not yet claimed.
--
-- Driven entirely by the welcomeBonus field in PlayerData (set server-side
-- in DataManager.processLogin, replicated via the existing GetPlayerData
-- call on join). No new remote needed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PlayerDataTemplate = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("PlayerDataTemplate"))

local WelcomeBanner = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local DISPLAY_DURATION = 5 -- seconds visible before fade
local FADE_DURATION = 0.5 -- seconds of fade-out animation
-- Pulled from PlayerDataTemplate.RETENTION so server's bonus-cap value and
-- this UI's "X more days for max" copy stay in sync. Bumping one without
-- the other previously caused mismatched messaging.
local MAX_STREAK_FOR_BONUS = PlayerDataTemplate.RETENTION.MAX_STREAK_FOR_BONUS

-- Track if banner has been shown this session to avoid re-showing on
-- subsequent GetPlayerData refreshes (e.g., after dragon select reload).
local shownThisSession = false

local screenGui: ScreenGui

function WelcomeBanner.create()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WelcomeBanner"
	screenGui.Enabled = false
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 15 -- above everything else; first impression
	screenGui.Parent = playerGui
end

-- Build a fresh banner card. Cheaper to rebuild on each show than persist a
-- hidden frame because show happens at most once per session.
local function buildCard(bonus: any): Frame
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 80)
	card.Size = UDim2.fromOffset(440, 220)
	card.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	card.BackgroundTransparency = 0.05
	card.BorderSizePixel = 0
	card.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 215, 0)
	stroke.Thickness = 3
	stroke.Parent = card

	-- Header: WELCOME BACK!
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -20, 0, 35)
	header.Position = UDim2.fromOffset(10, 12)
	header.BackgroundTransparency = 1
	header.Text = "WELCOME BACK!"
	header.TextColor3 = Color3.fromRGB(255, 215, 0)
	header.Font = Enum.Font.GothamBlack
	header.TextScaled = true
	header.Parent = card

	-- Streak line: 🔥 N Day Streak!
	local streakLine = Instance.new("TextLabel")
	streakLine.Size = UDim2.new(1, -20, 0, 36)
	streakLine.Position = UDim2.fromOffset(10, 55)
	streakLine.BackgroundTransparency = 1
	streakLine.TextColor3 = Color3.fromRGB(255, 120, 50)
	streakLine.Font = Enum.Font.GothamBold
	streakLine.TextScaled = true
	-- Day 1 isn't really a "streak" yet, just the start. Different copy on
	-- Day 1 reads more naturally and frames the streak as something to BUILD
	-- (not something they already have a 1-of). Day 2+ uses streak language.
	if bonus.streak == 1 then
		streakLine.Text = "🔥 Welcome — Day 1"
	else
		streakLine.Text = `🔥 {bonus.streak} Day Streak!`
	end
	streakLine.Parent = card

	-- Streak progress: "X more days for max streak" or "MAX STREAK 🔥"
	local progressLine = Instance.new("TextLabel")
	progressLine.Size = UDim2.new(1, -20, 0, 22)
	progressLine.Position = UDim2.fromOffset(10, 92)
	progressLine.BackgroundTransparency = 1
	progressLine.Font = Enum.Font.Gotham
	progressLine.TextScaled = true
	if bonus.streak >= MAX_STREAK_FOR_BONUS then
		progressLine.Text = "MAX STREAK 🔥"
		progressLine.TextColor3 = Color3.fromRGB(255, 200, 80)
	else
		local remaining = MAX_STREAK_FOR_BONUS - bonus.streak
		progressLine.Text = `{remaining} more day{if remaining == 1 then "" else "s"} for max streak`
		progressLine.TextColor3 = Color3.fromRGB(180, 180, 200)
	end
	progressLine.Parent = card

	-- Bonus breakdown line: +N coins (X daily + Y streak)
	local bonusLine = Instance.new("TextLabel")
	bonusLine.Size = UDim2.new(1, -20, 0, 32)
	bonusLine.Position = UDim2.fromOffset(10, 122)
	bonusLine.BackgroundTransparency = 1
	bonusLine.TextColor3 = Color3.fromRGB(255, 215, 0)
	bonusLine.Font = Enum.Font.GothamBold
	bonusLine.TextScaled = true
	-- Day 1 says "starter" instead of "streak" since calling +5 a streak bonus
	-- on the first day is weird. Day 2+ uses streak language to reinforce the
	-- compounding-reward mental model.
	if bonus.streak == 1 then
		bonusLine.Text = `+{bonus.totalCoins} coins ({bonus.dailyCoins} daily + {bonus.streakCoins} starter)`
	else
		bonusLine.Text = `+{bonus.totalCoins} coins ({bonus.dailyCoins} daily + {bonus.streakCoins} streak)`
	end
	bonusLine.Parent = card

	-- First-win tease (only if not already claimed today)
	local teaseLine = Instance.new("TextLabel")
	teaseLine.Size = UDim2.new(1, -20, 0, 28)
	teaseLine.Position = UDim2.fromOffset(10, 165)
	teaseLine.BackgroundTransparency = 1
	teaseLine.Font = Enum.Font.GothamMedium
	teaseLine.TextScaled = true
	if bonus.firstWinAvailable then
		teaseLine.Text = "🏆 First win today: +50 bonus"
		teaseLine.TextColor3 = Color3.fromRGB(180, 220, 255)
	else
		teaseLine.Text = "First win bonus already claimed today"
		teaseLine.TextColor3 = Color3.fromRGB(140, 140, 160)
	end
	teaseLine.Parent = card

	return card
end

-- Show the banner once per session. Subsequent calls are no-ops.
-- Pass the welcomeBonus table from PlayerData (server populates it on login).
function WelcomeBanner.show(bonus: any)
	if shownThisSession then return end
	if not bonus then return end
	if not screenGui then return end

	shownThisSession = true

	-- Clear any previous content (defensive — shouldn't happen but cheap)
	for _, child in screenGui:GetChildren() do
		child:Destroy()
	end

	local card = buildCard(bonus)
	screenGui.Enabled = true

	-- Slide-in from above the screen for a tiny bit of polish
	card.Position = UDim2.new(0.5, 0, 0, -250)
	local slideIn = TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 80),
	})
	slideIn:Play()

	-- After DISPLAY_DURATION, fade + slide out, then disable the GUI.
	task.delay(DISPLAY_DURATION, function()
		if not card or not card.Parent then return end
		local fadeOut = TweenService:Create(card, TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -250),
			BackgroundTransparency = 1,
		})
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if screenGui then screenGui.Enabled = false end
		end)
	end)
end

return WelcomeBanner
