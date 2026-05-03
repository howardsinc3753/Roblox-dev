--!strict
-- Round End Summary: shown briefly between RoundEnd and DragonSelectUI opening.
-- Displays the winner banner, top-3 leaderboard, and personal stats (kills,
-- deaths, coins earned this round). Auto-dismisses after a few seconds so the
-- intermission flow continues into Dragon Select.

local Players = game:GetService("Players")

local RoundEndSummary = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local screenGui: ScreenGui
local winnerLabel: TextLabel
local leaderboardFrame: Frame
local personalStatsLabel: TextLabel

local DISPLAY_DURATION = 6 -- seconds; intermission is 15s, then Dragon Select takes over

function RoundEndSummary.create()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RoundEndSummary"
	screenGui.Enabled = false
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 12 -- above DragonSelectUI (10) so it's visible first
	screenGui.Parent = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screenGui

	-- Centered card panel
	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(500, 400)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.Parent = screenGui

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 16)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(255, 215, 0)
	cardStroke.Thickness = 3
	cardStroke.Parent = card

	-- "ROUND OVER" header
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 35)
	header.Position = UDim2.fromOffset(0, 15)
	header.BackgroundTransparency = 1
	header.Text = "ROUND OVER"
	header.TextColor3 = Color3.fromRGB(255, 215, 0)
	header.Font = Enum.Font.GothamBlack
	header.TextScaled = true
	header.Parent = card

	-- Winner banner
	winnerLabel = Instance.new("TextLabel")
	winnerLabel.Name = "Winner"
	winnerLabel.Size = UDim2.new(1, -40, 0, 60)
	winnerLabel.Position = UDim2.fromOffset(20, 60)
	winnerLabel.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
	winnerLabel.BackgroundTransparency = 0.3
	winnerLabel.Text = "Winner: ???"
	winnerLabel.TextColor3 = Color3.new(1, 1, 1)
	winnerLabel.Font = Enum.Font.GothamBold
	winnerLabel.TextScaled = true
	winnerLabel.Parent = card

	local winnerCorner = Instance.new("UICorner")
	winnerCorner.CornerRadius = UDim.new(0, 8)
	winnerCorner.Parent = winnerLabel

	-- Leaderboard subheader
	local lbHeader = Instance.new("TextLabel")
	lbHeader.Size = UDim2.new(1, -40, 0, 25)
	lbHeader.Position = UDim2.fromOffset(20, 135)
	lbHeader.BackgroundTransparency = 1
	lbHeader.Text = "TOP PLAYERS"
	lbHeader.TextColor3 = Color3.fromRGB(180, 180, 200)
	lbHeader.Font = Enum.Font.GothamBold
	lbHeader.TextSize = 16
	lbHeader.TextXAlignment = Enum.TextXAlignment.Left
	lbHeader.Parent = card

	-- Leaderboard list (top 3)
	leaderboardFrame = Instance.new("Frame")
	leaderboardFrame.Name = "Leaderboard"
	leaderboardFrame.Size = UDim2.new(1, -40, 0, 110)
	leaderboardFrame.Position = UDim2.fromOffset(20, 165)
	leaderboardFrame.BackgroundTransparency = 1
	leaderboardFrame.Parent = card

	local lbLayout = Instance.new("UIListLayout")
	lbLayout.SortOrder = Enum.SortOrder.LayoutOrder
	lbLayout.Padding = UDim.new(0, 4)
	lbLayout.Parent = leaderboardFrame

	-- Personal stats footer
	personalStatsLabel = Instance.new("TextLabel")
	personalStatsLabel.Name = "PersonalStats"
	personalStatsLabel.Size = UDim2.new(1, -40, 0, 60)
	personalStatsLabel.Position = UDim2.new(0, 20, 1, -75)
	personalStatsLabel.BackgroundColor3 = Color3.fromRGB(40, 60, 40)
	personalStatsLabel.BackgroundTransparency = 0.3
	personalStatsLabel.Text = ""
	personalStatsLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	personalStatsLabel.Font = Enum.Font.GothamBold
	personalStatsLabel.TextScaled = true
	personalStatsLabel.Parent = card

	local statsCorner = Instance.new("UICorner")
	statsCorner.CornerRadius = UDim.new(0, 8)
	statsCorner.Parent = personalStatsLabel
end

local function clearLeaderboard()
	if not leaderboardFrame then return end
	for _, child in leaderboardFrame:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function addLeaderboardRow(rank: number, name: string, kills: number, deaths: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundColor3 = if rank == 1 then Color3.fromRGB(80, 60, 30) else Color3.fromRGB(40, 40, 50)
	row.BackgroundTransparency = 0.3
	row.LayoutOrder = rank
	row.Parent = leaderboardFrame

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 6)
	rowCorner.Parent = row

	local rankColor = (
		if rank == 1 then Color3.fromRGB(255, 215, 0) -- gold
		elseif rank == 2 then Color3.fromRGB(192, 192, 192) -- silver
		elseif rank == 3 then Color3.fromRGB(205, 127, 50) -- bronze
		else Color3.fromRGB(180, 180, 180)
	)

	local rankLabel = Instance.new("TextLabel")
	rankLabel.Size = UDim2.fromOffset(40, 30)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Text = `#{rank}`
	rankLabel.TextColor3 = rankColor
	rankLabel.Font = Enum.Font.GothamBold
	rankLabel.TextScaled = true
	rankLabel.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -180, 1, 0)
	nameLabel.Position = UDim2.fromOffset(45, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = name
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = row

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Size = UDim2.new(0, 130, 1, 0)
	statsLabel.Position = UDim2.new(1, -135, 0, 0)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Text = `{kills}K / {deaths}D`
	statsLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	statsLabel.Font = Enum.Font.GothamBold
	statsLabel.TextSize = 16
	statsLabel.TextXAlignment = Enum.TextXAlignment.Right
	statsLabel.Parent = row
end

-- scoreboard: { { userId, name, kills, deaths }, ... } sorted desc by kills
-- coinsEarned: { [userId]: number } per-player end-of-round payout
-- firstWinClaimed: { [userId]: boolean } true if THIS player just claimed their
--   first-win-of-day bonus this round. Lets the local player see a gold
--   "FIRST WIN TODAY +50" line as the daily-bonus payoff moment.
function RoundEndSummary.show(
	winnerUserId: number,
	scoreboard: { any },
	coinsEarned: { [number]: number }?,
	firstWinClaimed: { [number]: boolean }?
)
	if not screenGui then return end

	-- Winner banner
	if winnerUserId == 0 then
		winnerLabel.Text = "No Winner"
	else
		local winner = Players:GetPlayerByUserId(winnerUserId)
		local winnerName = if winner then winner.Name else "???"
		local winnerKills = 0
		for _, entry in scoreboard do
			if entry.userId == winnerUserId then
				winnerKills = entry.kills
				break
			end
		end
		winnerLabel.Text = `🏆 {winnerName} ({winnerKills} kills)`
	end

	-- Leaderboard top 3
	clearLeaderboard()
	for i = 1, math.min(3, #scoreboard) do
		local entry = scoreboard[i]
		addLeaderboardRow(i, entry.name, entry.kills, entry.deaths)
	end

	-- Personal stats
	local myKills, myDeaths = 0, 0
	for _, entry in scoreboard do
		if entry.userId == player.UserId then
			myKills = entry.kills
			myDeaths = entry.deaths
			break
		end
	end
	local myCoins = if coinsEarned then (coinsEarned[player.UserId] or 0) else 0
	local iClaimedFirstWin = firstWinClaimed and firstWinClaimed[player.UserId] == true
	if iClaimedFirstWin then
		-- Gold-tinted line + bigger font weight emphasis. The +50 is already
		-- baked into myCoins so no double-counting.
		personalStatsLabel.Text = `You: {myKills} kills, {myDeaths} deaths\n+{myCoins} coins earned  🏆 FIRST WIN TODAY!`
		personalStatsLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	else
		personalStatsLabel.Text = `You: {myKills} kills, {myDeaths} deaths\n+{myCoins} coins earned`
		personalStatsLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	end

	screenGui.Enabled = true

	-- Auto-dismiss after DISPLAY_DURATION. Uses a generation counter so a
	-- new round-end mid-display doesn't cause a stale timer to hide the new
	-- summary. (Edge case but cheap to guard.)
	local generation = (screenGui:GetAttribute("Generation") or 0) + 1
	screenGui:SetAttribute("Generation", generation)
	task.delay(DISPLAY_DURATION, function()
		if screenGui:GetAttribute("Generation") == generation then
			screenGui.Enabled = false
		end
	end)
end

function RoundEndSummary.hide()
	if screenGui then
		screenGui.Enabled = false
	end
end

return RoundEndSummary
