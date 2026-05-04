--!strict
-- Sprint 5 Part C/D companion UI: shows a "🏠 SAFE ZONE" pill at the top
-- center of the screen whenever Player:GetAttribute("Zone") == "Lair".
-- Server (ZoneManager) is the source of truth — this just observes.
--
-- Self-contained ScreenGui (no HUD.luau modifications) so a syntax error
-- here can't take the rest of the HUD down with it. The Sprint 5 HUD bug
-- showed how fragile init.client.luau is to the chain "HUD fails to load →
-- everything fails" — keeping the safe-zone label in its own module
-- preserves blast-radius isolation.

local Players = game:GetService("Players")

local SafeZoneIndicator = {}

local player = Players.LocalPlayer

local screenGui: ScreenGui? = nil
local label: TextLabel? = nil

local function ensureGui()
	if screenGui then return end
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SafeZoneIndicator"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 7 -- above HUD round-timer (which sits at 5-6 zone)
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	-- Pill: rounded background + emoji-prefixed text. Top-center so kids see
	-- it the moment they spawn into the Lair without it competing with health
	-- (top-left) or coins (top-right).
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromOffset(220, 40)
	pill.Position = UDim2.new(0.5, -110, 0, 16)
	pill.BackgroundColor3 = Color3.fromRGB(40, 90, 160)
	pill.BackgroundTransparency = 0.15
	pill.BorderSizePixel = 0
	pill.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 20)
	corner.Parent = pill

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 200, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = pill

	local txt = Instance.new("TextLabel")
	txt.Name = "Label"
	txt.Size = UDim2.fromScale(1, 1)
	txt.BackgroundTransparency = 1
	txt.Text = "🏠  SAFE ZONE"
	txt.TextColor3 = Color3.fromRGB(220, 240, 255)
	txt.TextStrokeTransparency = 0.5
	txt.Font = Enum.Font.GothamBlack
	txt.TextSize = 18
	txt.Parent = pill

	label = txt
end

local function setVisible(isInLair: boolean)
	ensureGui()
	if screenGui then
		screenGui.Enabled = isInLair
	end
end

function SafeZoneIndicator.init()
	ensureGui()

	-- Read initial state. The server stamps "Zone" at PlayerAdded, but
	-- replication ordering means the attribute may not exist yet when this
	-- module runs — default to Lair (matches spawn behavior).
	local zone = player:GetAttribute("Zone")
	setVisible(zone == nil or zone == "Lair")

	player:GetAttributeChangedSignal("Zone"):Connect(function()
		local newZone = player:GetAttribute("Zone")
		setVisible(newZone == "Lair")
	end)
end

return SafeZoneIndicator
