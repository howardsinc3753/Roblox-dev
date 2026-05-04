--!strict
-- Sprint 6: wave-state HUD. Subscribes to WaveStateChanged events and
-- renders the appropriate banner / counter / countdown for each phase
-- of the new wave loop.
--
-- States it handles:
--   INCOMING — big red "WAVE X INCOMING" banner with pulse, 3-sec telegraph
--   ACTIVE   — top-center "Wave X — N enemies left" pill (counter ticks down)
--   CLEARED  — "WAVE CLEAR! +N coins" celebratory flash + reward chime
--   TIMEOUT  — "Wave X timed out" muted notice (no bonus, but round advances)
--   RESTING  — "Wave X+1 starts in Ns..." countdown + first-time Lair tip
--
-- Self-contained ScreenGui — does not modify HUD.luau. Same isolation
-- pattern as SafeZoneIndicator (Sprint 5): if this module has a syntax
-- error, only the wave UI breaks, the rest of the HUD survives.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Sibling module — same client script container. Used for the wave-clear
-- "ding" reward sound; reusing the existing Coin asset is a no-cost win
-- vs. introducing a dedicated wave-clear SoundManager entry.
local SoundManager = require(script.Parent.SoundManager)

local WaveTracker = {}

local player = Players.LocalPlayer

-- UI element references (created in init, mutated by handle*State).
local screenGui: ScreenGui? = nil
local mainBanner: TextLabel? = nil
local mainPanel: Frame? = nil
local subtitle: TextLabel? = nil
local clearFlash: Frame? = nil

-- Once-per-session flag for the "visit your Lair between waves" tip.
-- The first time the player observes a RESTING state, we show the tip
-- briefly. Subsequent rest periods skip it (kid already learned).
local hasShownLairTip = false

local function ensureGui()
	if screenGui then return end
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WaveTracker"
	screenGui.ResetOnSpawn = false
	-- IgnoreGuiInset = false matches HUD's behavior (HUD doesn't set it,
	-- so default false). On systems with the Roblox top status bar
	-- (~36px), having one pill ignore the inset and the other not caused
	-- them to overlap visually. With both respecting the inset, the
	-- 20-pixel gap between y=10-60 (HUD) and y=80-140 (us) is preserved
	-- everywhere.
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 8 -- above HUD round-timer, below modal panels (DragonSelect=10)
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	-- Main panel: positioned top-center under the HUD round-timer area.
	-- HUD round-timer sits at y=10-60; pre-Sprint-6 we put this at y=70
	-- with no margin and the two visually crowded each other. Now y=80
	-- with a 20px gap between them so they read as separate elements.
	-- All states show their text in mainBanner inside this panel.
	mainPanel = Instance.new("Frame")
	mainPanel.Name = "Panel"
	mainPanel.Size = UDim2.fromOffset(420, 60)
	mainPanel.Position = UDim2.new(0.5, -210, 0, 80)
	mainPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	mainPanel.BackgroundTransparency = 0.2
	mainPanel.BorderSizePixel = 0
	mainPanel.Parent = screenGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = mainPanel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Name = "PanelStroke"
	panelStroke.Color = Color3.fromRGB(255, 60, 60)
	panelStroke.Thickness = 2
	panelStroke.Transparency = 0.3
	panelStroke.Parent = mainPanel

	mainBanner = Instance.new("TextLabel")
	mainBanner.Name = "Banner"
	mainBanner.Size = UDim2.fromScale(1, 1)
	mainBanner.BackgroundTransparency = 1
	mainBanner.Text = ""
	mainBanner.TextColor3 = Color3.fromRGB(255, 220, 220)
	mainBanner.TextStrokeTransparency = 0.4
	mainBanner.Font = Enum.Font.GothamBlack
	mainBanner.TextSize = 22
	mainBanner.Parent = mainPanel

	-- Subtitle: optional smaller line under the panel for tips/details
	-- (e.g. the first-time Lair tip during the first rest period).
	subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.fromOffset(420, 28)
	subtitle.Position = UDim2.new(0.5, -210, 0, 148)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = ""
	subtitle.TextColor3 = Color3.fromRGB(255, 230, 100)
	subtitle.TextStrokeTransparency = 0.5
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextSize = 16
	subtitle.Visible = false
	subtitle.Parent = screenGui

	-- Clear-flash overlay: big translucent green pulse on wave clear.
	-- Fades over ~1s. Drawn full-screen above the panel for celebration.
	clearFlash = Instance.new("Frame")
	clearFlash.Name = "ClearFlash"
	clearFlash.Size = UDim2.fromScale(1, 1)
	clearFlash.BackgroundColor3 = Color3.fromRGB(80, 255, 100)
	clearFlash.BackgroundTransparency = 1
	clearFlash.BorderSizePixel = 0
	clearFlash.ZIndex = -1 -- behind banner so text is readable
	clearFlash.Parent = screenGui
end

-- Helpers to set the panel theme per state. Stroke color reads as the
-- "what's happening now" signal: red = danger (incoming/active), green
-- = win (cleared), yellow = downtime (resting), grey = neutral (timeout).
local function setPanelTheme(strokeColor: Color3, bannerColor: Color3)
	if not mainPanel or not mainBanner then return end
	local stroke = mainPanel:FindFirstChild("PanelStroke") :: UIStroke?
	if stroke then stroke.Color = strokeColor end
	mainBanner.TextColor3 = bannerColor
end

local function showSubtitle(text: string, durationSec: number)
	if not subtitle then return end
	subtitle.Text = text
	subtitle.Visible = true
	-- Generation guard so a back-to-back showSubtitle doesn't get its hide
	-- task fired prematurely by the previous call's task.delay.
	local gen = (subtitle:GetAttribute("Generation") or 0) + 1
	subtitle:SetAttribute("Generation", gen)
	task.delay(durationSec, function()
		if subtitle and subtitle:GetAttribute("Generation") == gen then
			subtitle.Visible = false
		end
	end)
end

local function flashClear()
	if not clearFlash then return end
	clearFlash.BackgroundTransparency = 0.6
	-- Tween back to fully transparent over ~0.8s. EasingStyle.Quad keeps
	-- the celebration feeling snappy without a harsh cut.
	local tween = TweenService:Create(clearFlash, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})
	tween:Play()
end

-- State handlers. Each takes the payload table fired from the server.
local function handleIncoming(waveNum: number, payload: any)
	if not screenGui or not mainBanner then return end
	screenGui.Enabled = true
	local label = if payload and payload.isBossWave then `⚠️  BOSS WAVE INCOMING  ⚠️` else `WAVE {waveNum} INCOMING`
	mainBanner.Text = label
	setPanelTheme(Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 200, 200))
end

local function handleActive(waveNum: number, payload: any)
	if not screenGui or not mainBanner then return end
	screenGui.Enabled = true
	local enemiesLeft = (payload and payload.enemiesLeft) or 0
	local total = (payload and payload.totalEnemies) or 0
	local prefix = if payload and payload.isBossWave then "BOSS WAVE" else `Wave {waveNum}`
	mainBanner.Text = `{prefix}  —  {enemiesLeft} / {total} enemies`
	setPanelTheme(Color3.fromRGB(255, 100, 60), Color3.fromRGB(255, 230, 230))
end

local function handleCleared(waveNum: number, payload: any)
	if not screenGui or not mainBanner then return end
	screenGui.Enabled = true
	local reward = (payload and payload.coinReward) or 0
	mainBanner.Text = `✅ WAVE {waveNum} CLEAR! +{reward} coins`
	setPanelTheme(Color3.fromRGB(80, 220, 100), Color3.fromRGB(220, 255, 220))
	flashClear()
	-- Audio reward layered on the visual celebration. Coin is the existing
	-- "ding" SFX — kids respond hard to chimes after kills. No new asset.
	SoundManager.play("Coin")
end

local function handleTimeout(waveNum: number, _payload: any)
	if not screenGui or not mainBanner then return end
	screenGui.Enabled = true
	mainBanner.Text = `Wave {waveNum} timed out — advancing...`
	setPanelTheme(Color3.fromRGB(150, 150, 150), Color3.fromRGB(220, 220, 220))
end

local function handleResting(_waveNum: number, payload: any)
	if not screenGui or not mainBanner then return end
	screenGui.Enabled = true
	local secondsLeft = (payload and payload.secondsLeft) or 0
	local nextWave = (payload and payload.nextWave) or 0
	local nextIsBoss = payload and payload.nextIsBoss == true
	-- Boss pre-warn: when the upcoming wave is the boss, the rest pill
	-- shifts to the same red theme INCOMING uses for the boss wave. Without
	-- this, kids get a calm yellow countdown and then a sudden red boss
	-- banner — the boss wave deserves the "something big is coming"
	-- foreshadowing during the entire rest period.
	if nextIsBoss then
		mainBanner.Text = `⚠️  BOSS WAVE in {secondsLeft}s...`
		setPanelTheme(Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 220))
	else
		mainBanner.Text = `Wave {nextWave} starts in {secondsLeft}s...`
		setPanelTheme(Color3.fromRGB(255, 220, 100), Color3.fromRGB(255, 250, 200))
	end

	-- First-time-only tip: nudge the kid to use the Lair during the rest.
	-- Sprint 7 will add stat upgrades in the Lair so this becomes more
	-- actionable; for now it's a soft nudge to explore the safe zone.
	if not hasShownLairTip then
		hasShownLairTip = true
		showSubtitle("💡 Tip: portal to your Lair to catch your breath!", 6)
	end
end

local function handleRoundEnd()
	-- Hide the wave UI between rounds — RoundEndSummary takes over the
	-- screen real estate during the post-round window.
	if screenGui then
		screenGui.Enabled = false
	end
	if subtitle then
		subtitle.Visible = false
	end
end

function WaveTracker.init()
	ensureGui()

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	if not remotes then
		warn("[WaveTracker] No Remotes folder; aborting init")
		return
	end
	local waveStateChangedRemote = remotes:WaitForChild("WaveStateChanged", 10) :: RemoteEvent?
	local roundEndRemote = remotes:WaitForChild("RoundEnd", 10) :: RemoteEvent?
	if not waveStateChangedRemote then
		warn("[WaveTracker] WaveStateChanged remote missing; aborting init")
		return
	end

	waveStateChangedRemote.OnClientEvent:Connect(function(waveNum: number, waveState: string, payload: any)
		if waveState == "INCOMING" then
			handleIncoming(waveNum, payload)
		elseif waveState == "ACTIVE" then
			handleActive(waveNum, payload)
		elseif waveState == "CLEARED" then
			handleCleared(waveNum, payload)
		elseif waveState == "TIMEOUT" then
			handleTimeout(waveNum, payload)
		elseif waveState == "RESTING" then
			handleResting(waveNum, payload)
		end
	end)

	if roundEndRemote then
		roundEndRemote.OnClientEvent:Connect(handleRoundEnd)
	end
end

return WaveTracker
