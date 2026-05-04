--!strict
-- Sprint 7: stat-upgrade modal panel.
--
-- Opened by the Stat Stone obelisk's ProximityPrompt in the Lair. Shows:
--   - Tabbed dragon switcher at top (Ember, Frost, Storm🔒, ...) so a kid
--     who unlocked multiple dragons can upgrade any of them without
--     leaving the Lair (peer-review finding #1).
--   - Per-stat row: name, current value, level dots, next-upgrade cost
--     button OR "MAX" badge. Each row shows a preview of the bonus
--     ("Damage 15 → 20") so the kid sees what they're buying (peer #7).
--   - Confirmation prompt for purchases ≥200 coins (peer #8).
--   - First-time tutorial hint ("💡 Earn coins by killing enemies. Spend
--     them here to make your dragon stronger!") on first-ever open
--     (peer #15), persisted server-side via PlayerData.hasSeenLairTutorial.
--
-- Self-contained ScreenGui — same isolation pattern as SafeZoneIndicator
-- and WaveTracker. A syntax error in this module can't take HUD.luau down.
--
-- Server is authoritative for all stat values; this module just renders
-- the cache it receives via DragonStatsUpdated. No client-side stat math
-- (the cost curve, the per-stat magnitudes — all live in DragonProgression
-- on the server, replicated lazily as needed).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local DragonConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("DragonConfig"))
-- Sibling client modules — required to suspend gameplay input while the
-- modal is open. Without these the camera kept rotating with mouse
-- movement (because UserInputService.MouseBehavior=Default still fires
-- InputChanged for MouseMovement) and flight controls stayed hot, so a
-- kid trying to click an upgrade button was simultaneously yawing their
-- dragon and accidentally firing breath. POST-PLAYTEST: kid reported
-- "my mouse still controls me looking around, can't interface with the
-- menu" — this fixes it.
local FlightController = require(script.Parent.FlightController)
local CameraController = require(script.Parent.CameraController)
local CombatInput = require(script.Parent.CombatInput)
local SoundManager = require(script.Parent.SoundManager)

local DragonUpgradeUI = {}

local player = Players.LocalPlayer

-- ===== State (populated from server pushes) =====
local cachedCoins = 0
local unlockedDragons: { [string]: boolean } = { Ember = true, Frost = true }
local selectedDragon = "Ember" -- which dragon the kid is currently flying
local activeTab = "Ember"      -- which tab the modal is currently showing
local hasSeenTutorial = false

-- statsCache[dragonId] = { levels = {...}, effective = {...} }
local statsCache: { [string]: { levels: any, effective: any } } = {}

-- Stat metadata for rendering. Keys match PlayerData.dragonUpgrades and the
-- server's DragonProgression.STAT_KEYS. The `valueLabel` callback formats
-- the displayed current value per stat (HP for def, raw integer for everything
-- else). previewMagnitudes mirror DragonProgression's per-level numbers
-- so we can show "Damage 15 → 20" without a server round-trip — kept in
-- sync manually with the server. Mismatch = preview text is wrong but the
-- actual upgrade still applies correctly (server is authoritative).
local STAT_META = {
	{ key = "atk", label = "Attack", color = Color3.fromRGB(255, 100, 80), valueField = "damage", valueSuffix = " dmg", magnitude = 5 },
	{ key = "def", label = "Defense", color = Color3.fromRGB(120, 200, 255), valueField = "health", valueSuffix = " HP", magnitude = 10 },
	{ key = "spd", label = "Speed", color = Color3.fromRGB(255, 220, 100), valueField = "speed", valueSuffix = "", magnitude = 0 }, -- diminishing; computed
	{ key = "special", label = "Special", color = Color3.fromRGB(200, 120, 255), valueField = "specialDamage", valueSuffix = " dmg", magnitude = 5 },
}

-- Speed magnitude per next level (mirrors DragonProgression.SPD_BONUS_BY_LEVEL).
local SPD_PREVIEW_BY_NEXT_LEVEL = { 5, 3, 3, 2, 2 }

local COST_BY_LEVEL = { 25, 100, 200, 400, 800 }
local MAX_LEVEL = 5
local CONFIRM_THRESHOLD_COINS = 200

-- ===== UI references =====
local screenGui: ScreenGui? = nil
local card: Frame? = nil
local tabContainer: Frame? = nil
local statsContainer: Frame? = nil
local coinsLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil
local tutorialLabel: TextLabel? = nil
local confirmOverlay: Frame? = nil

-- Forward declaration so handlers can reference rebuild before it's defined.
local rebuild: () -> ()

-- ===== Remotes (set in init) =====
local upgradeStatRemote: RemoteEvent? = nil
local markLairTutorialSeenRemote: RemoteEvent? = nil
-- Sprint 7 polish: lets the upgrade modal also unlock dragons (kid
-- playtest feedback: "upgrade menu should allow you to BUY new dragons
-- in there as well as the B menu"). Same UnlockDragon remote the
-- existing DragonSelectUI fires — server validates funds + ownership
-- + flips unlockedDragons[id] = true → fires UpdateCoins back. We
-- listen to UpdateCoins via updateCoins() and PlayerData refreshes via
-- updatePlayerData(); both keep the modal's cached state in sync.
local unlockDragonRemote: RemoteEvent? = nil

-- ===== Helpers =====
local function getEffectiveValue(dragonId: string, valueField: string): number
	local entry = statsCache[dragonId]
	if entry and entry.effective then
		return entry.effective[valueField] or 0
	end
	-- No cache yet — fall back to DragonConfig base. Maps the EffectiveStats
	-- field names to the DragonConfig field name where they differ (none
	-- currently differ, but spelling them out makes future refactors safer).
	local base = DragonConfig[dragonId]
	if not base then return 0 end
	if valueField == "damage" or valueField == "specialDamage" then
		return base.damage
	elseif valueField == "health" then
		return base.health
	elseif valueField == "speed" then
		return base.speed
	end
	return 0
end

local function getLevels(dragonId: string)
	local entry = statsCache[dragonId]
	if entry and entry.levels then
		return entry.levels
	end
	return { atk = 0, def = 0, spd = 0, special = 0 }
end

local function previewDelta(statKey: string, currentLevel: number): number
	if statKey == "spd" then
		local nextLv = currentLevel + 1
		if nextLv < 1 or nextLv > MAX_LEVEL then return 0 end
		return SPD_PREVIEW_BY_NEXT_LEVEL[nextLv]
	end
	for _, meta in STAT_META do
		if meta.key == statKey then return meta.magnitude end
	end
	return 0
end

local function getDragonOrder(): { string }
	-- Tab order matches DragonSelectUI's grid order so the kid's mental
	-- map is consistent: Ember → Frost → Storm → Terra → Shadow → Prism.
	return { "Ember", "Frost", "Storm", "Terra", "Shadow", "Prism" }
end

-- ===== Confirmation overlay =====
local function showConfirm(title: string, onConfirm: () -> ())
	if not screenGui or not confirmOverlay then return end
	confirmOverlay:ClearAllChildren()

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel = 0
	backdrop.Parent = confirmOverlay

	local box = Instance.new("Frame")
	box.Size = UDim2.fromOffset(380, 160)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	box.BorderSizePixel = 0
	box.Parent = confirmOverlay

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 12)
	boxCorner.Parent = box

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 215, 0)
	stroke.Thickness = 2
	stroke.Parent = box

	local titleText = Instance.new("TextLabel")
	titleText.Size = UDim2.new(1, -30, 0, 60)
	titleText.Position = UDim2.fromOffset(15, 15)
	titleText.BackgroundTransparency = 1
	titleText.Text = title
	titleText.TextColor3 = Color3.fromRGB(255, 250, 220)
	titleText.Font = Enum.Font.GothamBold
	titleText.TextSize = 18
	titleText.TextWrapped = true
	titleText.Parent = box

	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Size = UDim2.fromOffset(150, 44)
	confirmBtn.Position = UDim2.new(1, -165, 1, -60)
	confirmBtn.BackgroundColor3 = Color3.fromRGB(80, 200, 100)
	confirmBtn.Text = "Confirm"
	confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	confirmBtn.Font = Enum.Font.GothamBold
	confirmBtn.TextSize = 18
	confirmBtn.BorderSizePixel = 0
	confirmBtn.Selectable = true -- gamepad: D-pad needs this to land here
	confirmBtn.Parent = box

	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0, 8)
	confirmCorner.Parent = confirmBtn

	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Size = UDim2.fromOffset(150, 44)
	cancelBtn.Position = UDim2.new(0, 15, 1, -60)
	cancelBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 110)
	cancelBtn.Text = "Cancel"
	cancelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	cancelBtn.Font = Enum.Font.GothamBold
	cancelBtn.TextSize = 18
	cancelBtn.BorderSizePixel = 0
	cancelBtn.Selectable = true -- gamepad
	cancelBtn.Parent = box

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 8)
	cancelCorner.Parent = cancelBtn

	confirmOverlay.Visible = true

	confirmBtn.Activated:Connect(function()
		confirmOverlay.Visible = false
		onConfirm()
	end)
	cancelBtn.Activated:Connect(function()
		confirmOverlay.Visible = false
	end)
end

-- ===== Send upgrade =====
local function sendUpgrade(dragonId: string, statKey: string)
	if not upgradeStatRemote then return end
	upgradeStatRemote:FireServer(dragonId, statKey)
end

local function handleUpgradeClick(dragonId: string, statKey: string, cost: number)
	if cachedCoins < cost then
		-- Audio cue + brief shake would be nice; for MVP just no-op silently.
		-- The button is rendered greyed-out so this is mostly a defensive guard.
		return
	end
	if cost >= CONFIRM_THRESHOLD_COINS then
		local meta
		for _, m in STAT_META do if m.key == statKey then meta = m end end
		local label = meta and meta.label or statKey
		showConfirm(`Spend {cost} coins on {label}?`, function()
			sendUpgrade(dragonId, statKey)
		end)
	else
		sendUpgrade(dragonId, statKey)
	end
end

-- ===== Stat row builder =====
local function buildStatRow(parent: Frame, dragonId: string, meta: any, layoutOrder: number)
	local levels = getLevels(dragonId)
	local currentLevel = levels[meta.key] or 0
	local maxed = currentLevel >= MAX_LEVEL
	local nextCost = if maxed then nil else COST_BY_LEVEL[currentLevel + 1]
	local canAfford = nextCost and cachedCoins >= nextCost

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 70)
	row.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
	row.BackgroundTransparency = 0.2
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.Parent = parent

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 10)
	rowCorner.Parent = row

	-- Stripe of stat color along left edge so the four rows are visually distinct
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 6, 1, 0)
	stripe.BackgroundColor3 = meta.color
	stripe.BorderSizePixel = 0
	stripe.Parent = row

	local stripeCorner = Instance.new("UICorner")
	stripeCorner.CornerRadius = UDim.new(0, 3)
	stripeCorner.Parent = stripe

	-- Left-side: stat name + current value + level dots
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromOffset(120, 24)
	nameLabel.Position = UDim2.fromOffset(20, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = meta.label
	nameLabel.TextColor3 = meta.color
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 18
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = row

	local currentValue = getEffectiveValue(dragonId, meta.valueField)
	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.fromOffset(140, 24)
	valueLabel.Position = UDim2.fromOffset(20, 36)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = `{math.floor(currentValue)}{meta.valueSuffix}`
	valueLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
	valueLabel.Font = Enum.Font.Gotham
	valueLabel.TextSize = 14
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.Parent = row

	-- Level dots (5 dots, filled = current level)
	local dotsContainer = Instance.new("Frame")
	dotsContainer.Size = UDim2.fromOffset(110, 18)
	dotsContainer.Position = UDim2.fromOffset(150, 9)
	dotsContainer.BackgroundTransparency = 1
	dotsContainer.Parent = row
	local dotsLayout = Instance.new("UIListLayout")
	dotsLayout.FillDirection = Enum.FillDirection.Horizontal
	dotsLayout.Padding = UDim.new(0, 4)
	dotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dotsLayout.Parent = dotsContainer
	for i = 1, MAX_LEVEL do
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(18, 18)
		dot.BackgroundColor3 = if i <= currentLevel then meta.color else Color3.fromRGB(60, 60, 75)
		dot.BorderSizePixel = 0
		dot.LayoutOrder = i
		dot.Parent = dotsContainer
		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(0.5, 0)
		dotCorner.Parent = dot
	end

	-- Preview text: "Damage 15 → 20" (peer #7). Skipped at MAX since there's
	-- nothing to preview.
	if not maxed then
		local delta = previewDelta(meta.key, currentLevel)
		local nextValue = currentValue + delta
		local previewLabel = Instance.new("TextLabel")
		previewLabel.Size = UDim2.fromOffset(180, 18)
		previewLabel.Position = UDim2.fromOffset(150, 36)
		previewLabel.BackgroundTransparency = 1
		previewLabel.Text = `Lv {currentLevel} → {currentLevel + 1}: {math.floor(currentValue)} → {math.floor(nextValue)}`
		previewLabel.TextColor3 = Color3.fromRGB(180, 220, 180)
		previewLabel.Font = Enum.Font.Gotham
		previewLabel.TextSize = 12
		previewLabel.TextXAlignment = Enum.TextXAlignment.Left
		previewLabel.Parent = row
	end

	-- Right-side: upgrade button OR MAX badge
	if maxed then
		local maxBadge = Instance.new("TextLabel")
		maxBadge.Size = UDim2.fromOffset(120, 40)
		maxBadge.Position = UDim2.new(1, -135, 0.5, -20)
		maxBadge.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
		maxBadge.Text = "★ MAX ★"
		maxBadge.TextColor3 = Color3.fromRGB(60, 40, 0)
		maxBadge.Font = Enum.Font.GothamBlack
		maxBadge.TextSize = 16
		maxBadge.BorderSizePixel = 0
		maxBadge.Parent = row
		local maxCorner = Instance.new("UICorner")
		maxCorner.CornerRadius = UDim.new(0, 8)
		maxCorner.Parent = maxBadge
	else
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromOffset(140, 44)
		btn.Position = UDim2.new(1, -155, 0.5, -22)
		btn.BackgroundColor3 = if canAfford then Color3.fromRGB(80, 180, 100) else Color3.fromRGB(80, 80, 90)
		btn.Text = `+ {nextCost} 🪙`
		btn.TextColor3 = if canAfford then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(160, 160, 170)
		btn.Font = Enum.Font.GothamBlack
		btn.TextSize = 18
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = canAfford
		btn.Active = canAfford
		-- Gamepad navigation: only the rows with an affordable upgrade are
		-- selectable. Non-affordable rows are still rendered so the kid sees
		-- what's possible, but D-pad skips them — same logic as the click
		-- gating above (`if canAfford then ... :Connect`).
		btn.Selectable = canAfford
		btn.Parent = row
		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 8)
		btnCorner.Parent = btn

		if canAfford then
			btn.Activated:Connect(function()
				handleUpgradeClick(dragonId, meta.key, nextCost :: number)
			end)
		end
	end
end

-- ===== Tab builder =====
local function buildTab(parent: Frame, dragonId: string, layoutOrder: number)
	local owned = unlockedDragons[dragonId] == true
	local active = activeTab == dragonId
	local base = DragonConfig[dragonId]
	if not base then return end

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(110, 36)
	btn.LayoutOrder = layoutOrder
	btn.BackgroundColor3 = if active then base.color else Color3.fromRGB(45, 45, 60)
	btn.Text = if owned then base.name else `🔒 {base.name}`
	btn.TextColor3 = if active then Color3.fromRGB(20, 20, 30) else (if owned then Color3.fromRGB(220, 220, 230) else Color3.fromRGB(140, 140, 150))
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true -- click both owned + locked tabs
	btn.Active = true
	btn.Selectable = true -- gamepad: D-pad needs to land on tab strip
	btn.Parent = parent
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = btn

	-- POST-PLAYTEST: locked tabs are NOW clickable too. Clicking a locked
	-- tab switches activeTab and rebuild() renders an unlock-buy panel
	-- instead of the upgrade rows. This delivers on the kid's "let me
	-- buy dragons here too" feedback without forcing them to leave the
	-- modal, port through to Arena, press B, etc.
	btn.Activated:Connect(function()
		if activeTab ~= dragonId then
			activeTab = dragonId
			rebuild()
		end
	end)
end

-- ===== Locked-dragon buy panel =====
-- Renders inside `statsContainer` when activeTab is a dragon the player
-- doesn't own yet. Single big "Unlock for {cost} 🪙" button + dragon
-- preview stats so kids can see what they're buying. Click fires
-- UnlockDragon (same remote DragonSelectUI uses); server validates funds
-- and replies via UpdateCoins → our updateCoins handler refreshes the
-- modal. The kid sees the dragon's tab go from 🔒 to ✓ on their next
-- modal open or rebuild trigger.
local function buildUnlockPanel(parent: Frame, dragonId: string)
	local base = DragonConfig[dragonId]
	if not base then return end
	local cost = base.cost or 0
	local canAfford = cachedCoins >= cost

	-- Header: dragon name + element + base stats
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 30)
	header.BackgroundTransparency = 1
	header.Text = `🔒 {base.name} — {base.element}`
	header.TextColor3 = base.color
	header.Font = Enum.Font.GothamBlack
	header.TextSize = 22
	header.LayoutOrder = 1
	header.Parent = parent

	-- Base stats preview (HP / DMG / SPD / Special). Reads from DragonConfig
	-- since we don't have a per-player effective-stats cache for locked dragons.
	local statsPreview = Instance.new("TextLabel")
	statsPreview.Size = UDim2.new(1, 0, 0, 60)
	statsPreview.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
	statsPreview.BackgroundTransparency = 0.2
	statsPreview.BorderSizePixel = 0
	statsPreview.Text = `❤️ {base.health} HP    ⚔️ {base.damage} DMG    💨 {base.speed} SPD\n✨ {base.specialName}`
	statsPreview.TextColor3 = Color3.fromRGB(220, 220, 235)
	statsPreview.Font = Enum.Font.GothamBold
	statsPreview.TextSize = 16
	statsPreview.LayoutOrder = 2
	statsPreview.Parent = parent
	local previewCorner = Instance.new("UICorner")
	previewCorner.CornerRadius = UDim.new(0, 8)
	previewCorner.Parent = statsPreview

	-- Big buy button. Greyed out if can't afford.
	local buyBtn = Instance.new("TextButton")
	buyBtn.Size = UDim2.new(1, 0, 0, 60)
	buyBtn.BackgroundColor3 = if canAfford then Color3.fromRGB(80, 200, 100) else Color3.fromRGB(80, 80, 90)
	buyBtn.Text = if canAfford then `🔓 UNLOCK for {cost} 🪙` else `Need {cost - cachedCoins} more 🪙`
	buyBtn.TextColor3 = if canAfford then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(160, 160, 170)
	buyBtn.Font = Enum.Font.GothamBlack
	buyBtn.TextSize = 22
	buyBtn.BorderSizePixel = 0
	buyBtn.AutoButtonColor = canAfford
	buyBtn.Active = canAfford
	buyBtn.Selectable = canAfford -- gamepad: only navigable when actually buyable
	buyBtn.LayoutOrder = 3
	buyBtn.Parent = parent
	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 10)
	buyCorner.Parent = buyBtn
	if canAfford then
		buyBtn.Activated:Connect(function()
			if not unlockDragonRemote then return end
			-- Optimistic UI: assume the server will accept (we already
			-- validated funds above). If server rejects, the next
			-- PlayerData refresh will re-grey the dragon and the kid
			-- sees "huh, didn't go through" — rare and self-correcting.
			unlockDragonRemote:FireServer(dragonId)
			SoundManager.play("Purchase")
			unlockedDragons[dragonId] = true
			cachedCoins -= cost
			rebuild() -- redraw to show the now-owned dragon's stat rows
		end)
	end
end

-- ===== Main rebuild =====
rebuild = function()
	if not screenGui or not card or not tabContainer or not statsContainer then return end

	-- Title: dragon name + element
	local base = DragonConfig[activeTab]
	if base and titleLabel then
		titleLabel.Text = `{base.name} — {base.element}`
		titleLabel.TextColor3 = base.color
	end

	-- Coins display
	if coinsLabel then
		coinsLabel.Text = `{cachedCoins} 🪙`
	end

	-- Tabs
	tabContainer:ClearAllChildren()
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabContainer
	local order = 1
	for _, dragonId in getDragonOrder() do
		buildTab(tabContainer, dragonId, order)
		order += 1
	end

	-- Stat rows OR unlock-buy panel depending on whether the active tab
	-- is owned. Locked dragon → render the buy panel; owned → standard
	-- four upgrade rows.
	statsContainer:ClearAllChildren()
	local statsLayout = Instance.new("UIListLayout")
	statsLayout.Padding = UDim.new(0, 8)
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Parent = statsContainer
	if not unlockedDragons[activeTab] then
		buildUnlockPanel(statsContainer, activeTab)
	else
		for i, meta in STAT_META do
			buildStatRow(statsContainer, activeTab, meta, i)
		end
	end
end

-- ===== Public API =====
function DragonUpgradeUI.create()
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DragonUpgradeUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 11 -- above DragonSelectUI (10), below RoundEndSummary (12)
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	-- Backdrop dims the world; click-through to close.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BorderSizePixel = 0
	-- Explicitly NOT navigable: full-screen click-to-close target, but we
	-- don't want D-pad to ever land here (it'd consume the cursor instead
	-- of letting it cycle through tabs/upgrade buttons). Mouse + touch can
	-- still click it directly.
	backdrop.Selectable = false
	backdrop.Parent = screenGui
	backdrop.Activated:Connect(function() DragonUpgradeUI.close() end)

	card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(560, 540)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.BackgroundColor3 = Color3.fromRGB(25, 25, 38)
	card.BorderSizePixel = 0
	card.Parent = screenGui
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 16)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(255, 215, 0)
	cardStroke.Thickness = 3
	cardStroke.Parent = card

	-- Header
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -40, 0, 36)
	header.Position = UDim2.fromOffset(20, 16)
	header.BackgroundTransparency = 1
	header.Text = "🔱  STAT STONE"
	header.TextColor3 = Color3.fromRGB(255, 215, 0)
	header.Font = Enum.Font.GothamBlack
	header.TextSize = 22
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = card

	-- Coins (top-right)
	coinsLabel = Instance.new("TextLabel")
	coinsLabel.Size = UDim2.fromOffset(160, 36)
	coinsLabel.Position = UDim2.new(1, -180, 0, 16)
	coinsLabel.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
	coinsLabel.BackgroundTransparency = 0.2
	coinsLabel.BorderSizePixel = 0
	coinsLabel.Text = "0 🪙"
	coinsLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	coinsLabel.Font = Enum.Font.GothamBlack
	coinsLabel.TextSize = 18
	coinsLabel.Parent = card
	local coinsCorner = Instance.new("UICorner")
	coinsCorner.CornerRadius = UDim.new(0, 8)
	coinsCorner.Parent = coinsLabel

	-- Close (X) — top-right above coins. Small, tap target ~30x30.
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(34, 34)
	closeBtn.Position = UDim2.new(1, -42, 0, -10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 18
	closeBtn.BorderSizePixel = 0
	closeBtn.Selectable = true -- gamepad
	closeBtn.Parent = card
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0.5, 0)
	closeCorner.Parent = closeBtn
	closeBtn.Activated:Connect(function() DragonUpgradeUI.close() end)

	-- Title (active dragon name)
	titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -40, 0, 26)
	titleLabel.Position = UDim2.fromOffset(20, 60)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Ember"
	titleLabel.TextColor3 = Color3.fromRGB(255, 100, 50)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 20
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = card

	-- Tab container (dragon switcher)
	tabContainer = Instance.new("Frame")
	tabContainer.Size = UDim2.new(1, -40, 0, 40)
	tabContainer.Position = UDim2.fromOffset(20, 92)
	tabContainer.BackgroundTransparency = 1
	tabContainer.Parent = card

	-- Stat rows container
	statsContainer = Instance.new("Frame")
	statsContainer.Size = UDim2.new(1, -40, 0, 320)
	statsContainer.Position = UDim2.fromOffset(20, 144)
	statsContainer.BackgroundTransparency = 1
	statsContainer.Parent = card

	-- Tutorial hint banner. Placed at bottom, visible only on first open.
	-- Self-hides after 8 seconds. Replaces with persistent flag via remote.
	tutorialLabel = Instance.new("TextLabel")
	tutorialLabel.Size = UDim2.new(1, -40, 0, 50)
	tutorialLabel.Position = UDim2.new(0, 20, 1, -64)
	tutorialLabel.BackgroundColor3 = Color3.fromRGB(40, 60, 80)
	tutorialLabel.BackgroundTransparency = 0.2
	tutorialLabel.BorderSizePixel = 0
	tutorialLabel.Text = "💡 Earn coins by killing enemies. Spend them here to make your dragon stronger!"
	tutorialLabel.TextColor3 = Color3.fromRGB(255, 240, 180)
	tutorialLabel.Font = Enum.Font.GothamBold
	tutorialLabel.TextSize = 14
	tutorialLabel.TextWrapped = true
	tutorialLabel.Visible = false
	tutorialLabel.Parent = card
	local tutorialCorner = Instance.new("UICorner")
	tutorialCorner.CornerRadius = UDim.new(0, 8)
	tutorialCorner.Parent = tutorialLabel

	-- Confirm overlay (full-screen, on top of card). Hidden by default;
	-- shown by showConfirm() above.
	confirmOverlay = Instance.new("Frame")
	confirmOverlay.Name = "ConfirmOverlay"
	confirmOverlay.Size = UDim2.fromScale(1, 1)
	confirmOverlay.BackgroundTransparency = 1
	confirmOverlay.BorderSizePixel = 0
	confirmOverlay.Visible = false
	confirmOverlay.ZIndex = 5
	confirmOverlay.Parent = screenGui
end

function DragonUpgradeUI.open()
	if not screenGui then return end
	-- Default to the kid's currently-flying dragon when opening so they see
	-- "their" stats first. They can tap a tab to switch.
	activeTab = if unlockedDragons[selectedDragon] then selectedDragon else "Ember"
	rebuild()

	-- POST-PLAYTEST FIX: suspend gameplay input while the modal is open.
	-- Three things to handle:
	--   1. Mouse: free the cursor so the kid can click upgrade buttons.
	--   2. Camera: stop reading mouse delta so cursor movement doesn't
	--      yaw the dragon while they're trying to aim at a button.
	--   3. Flight + Combat: WASD/Space/LMB/RMB shouldn't move the dragon
	--      or fire breath through the modal.
	-- All restored on close. Trust round-state events (RoundStart /
	-- RoundEnd / death) to override our restoration if the round
	-- transitioned while the modal was open — those handlers are
	-- idempotent.
	--
	-- These run BEFORE screenGui.Enabled = true so there's no sub-frame
	-- window where the modal is visible but flight/combat are still hot
	-- (a click during that window would fire breath through the modal).
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	CameraController.disable()
	FlightController.disable()
	-- halt() zeros velocity in addition to gating input — without this
	-- the dragon keeps drifting in the last commanded direction the whole
	-- time the modal is open (LinearVelocity constraint persists).
	FlightController.halt()
	CombatInput.disable()

	screenGui.Enabled = true

	-- Gamepad navigation (Xbox playtest target): set a sensible default
	-- selection so D-pad works immediately. Picks the first stat row's
	-- upgrade button; falls back gracefully if nothing's clickable.
	-- Uses the module-level `statsContainer` ref directly (the Frames
	-- intentionally don't have Names set, so a recursive find wouldn't
	-- work).
	if statsContainer then
		for _, row in statsContainer:GetChildren() do
			if row:IsA("Frame") then
				local btn = row:FindFirstChildWhichIsA("TextButton")
				if btn and btn.Active then
					GuiService.SelectedObject = btn
					break
				end
			end
		end
	end

	-- First-visit tutorial hint (peer #15). Tracks both client-session-flag
	-- and server PlayerData.hasSeenLairTutorial. Either being true skips
	-- the hint. Server flip happens via the MarkLairTutorialSeen remote
	-- the first time we render it so a quit-and-rejoin doesn't replay.
	if not hasSeenTutorial and tutorialLabel then
		tutorialLabel.Visible = true
		hasSeenTutorial = true
		if markLairTutorialSeenRemote then
			markLairTutorialSeenRemote:FireServer()
		end
		task.delay(8, function()
			if tutorialLabel then tutorialLabel.Visible = false end
		end)
	end
end

function DragonUpgradeUI.close()
	if screenGui then screenGui.Enabled = false end
	if confirmOverlay then confirmOverlay.Visible = false end

	-- Restore gameplay input. See open() for why we disabled them.
	-- MouseBehavior only meaningful when there's a mouse — touch / gamepad-
	-- only sessions don't have one and Roblox no-ops the call there, but
	-- guarding explicitly mirrors the pattern CameraController.enable()
	-- already uses.
	if UserInputService.MouseEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
	CameraController.enable()
	FlightController.enable()
	CombatInput.enable()

	-- Release the gamepad selection so the D-pad doesn't keep navigating
	-- a now-hidden modal.
	GuiService.SelectedObject = nil
end

function DragonUpgradeUI.isOpen(): boolean
	return screenGui ~= nil and screenGui.Enabled
end

-- Server pushes (called from remote handlers in init.client.luau OR wired
-- inline by DragonUpgradeUI.init below).
function DragonUpgradeUI.updateCoins(coins: number)
	cachedCoins = coins
	if screenGui and screenGui.Enabled then rebuild() end
end

function DragonUpgradeUI.updateStats(dragonId: string, levels: any, effective: any)
	-- Detect a level-up since the last cached state. If any stat went UP,
	-- the kid just made a successful purchase — play the dedicated
	-- Purchase chime so they hear the spend (the existing per-coin "Coin"
	-- ding plays on every UpdateCoins so it doesn't read as ceremony).
	-- Skipped on the FIRST update for a dragon (no previous state to
	-- compare against) so the initial DragonStatsUpdated fired by
	-- processPlayer / SelectDragon doesn't false-trigger the chime.
	local previous = statsCache[dragonId]
	if previous and previous.levels and levels then
		local prev = previous.levels
		if (levels.atk or 0) > (prev.atk or 0)
			or (levels.def or 0) > (prev.def or 0)
			or (levels.spd or 0) > (prev.spd or 0)
			or (levels.special or 0) > (prev.special or 0) then
			SoundManager.play("Purchase")
		end
	end
	statsCache[dragonId] = { levels = levels, effective = effective }
	if screenGui and screenGui.Enabled and activeTab == dragonId then rebuild() end
end

function DragonUpgradeUI.setSelectedDragon(dragonId: string)
	selectedDragon = dragonId
end

function DragonUpgradeUI.updatePlayerData(data: any)
	if not data then return end
	if data.coins then cachedCoins = data.coins end
	if data.unlockedDragons then unlockedDragons = data.unlockedDragons end
	if data.selectedDragon then
		selectedDragon = data.selectedDragon
	end
	if data.hasSeenLairTutorial == true then hasSeenTutorial = true end
	if data.dragonUpgrades then
		for dragonId, lv in data.dragonUpgrades do
			if not statsCache[dragonId] then
				statsCache[dragonId] = { levels = lv, effective = nil }
			else
				statsCache[dragonId].levels = lv
			end
		end
	end
	if screenGui and screenGui.Enabled then rebuild() end
end

function DragonUpgradeUI.init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	if not remotes then
		warn("[DragonUpgradeUI] No Remotes folder; aborting init")
		return
	end
	upgradeStatRemote = remotes:WaitForChild("UpgradeStat", 10) :: RemoteEvent?
	-- MarkLairTutorialSeen is wired in a follow-up step; fall back to nil
	-- gracefully if it's not yet registered.
	markLairTutorialSeenRemote = remotes:FindFirstChild("MarkLairTutorialSeen") :: RemoteEvent?
	-- Dragon unlock — same remote DragonSelectUI fires.
	unlockDragonRemote = remotes:WaitForChild("UnlockDragon", 10) :: RemoteEvent?

	local dragonStatsUpdated = remotes:WaitForChild("DragonStatsUpdated", 10) :: RemoteEvent?
	if dragonStatsUpdated then
		dragonStatsUpdated.OnClientEvent:Connect(function(dragonId: string, levels: any, effective: any)
			DragonUpgradeUI.updateStats(dragonId, levels, effective)
		end)
	end

	-- Esc / Xbox B to close (when open). UserInputService is gameProcessed-
	-- aware so we don't fight TextBox focus or other modals. ButtonB is
	-- the standard Xbox "back" gesture so kids transferring from the PC
	-- demo to console don't have to relearn the close path.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if not DragonUpgradeUI.isOpen() then return end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			DragonUpgradeUI.close()
		end
	end)
end

return DragonUpgradeUI
