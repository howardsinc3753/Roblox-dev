--!strict
-- Dragon Select UI: modal panel shown during round intermission.
-- Players pick which dragon to spawn as next round, or buy locked dragons
-- with coins they've earned.
--
-- Visual: dimmed background overlay + grid of 6 dragon cards + close hint.
-- Locked dragons render greyed out with cost; clicking attempts purchase.
-- Selected dragon gets a colored border. Clicking an unlocked dragon
-- selects it and fires SelectDragon remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DragonConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("DragonConfig"))

local DragonSelectUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- Persistent UI state — re-rendered when data changes
local screenGui: ScreenGui
local dragonCards: { [string]: { card: Frame, status: TextLabel } } = {}
local cachedCoins = 0
local cachedSelected = "Ember"
local cachedUnlocks: { [string]: boolean } = { Ember = true, Frost = true }

-- Remotes
local selectDragonRemote: RemoteEvent?
local unlockDragonRemote: RemoteEvent?

-- Render order for the grid: free dragons first, then by cost ascending.
-- This means the unlocked dragons appear in the obvious "starter" slots and
-- the unlock progression reads left-to-right by cost.
local DRAGON_ORDER = { "Ember", "Frost", "Storm", "Terra", "Shadow", "Prism" }

function DragonSelectUI.init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	selectDragonRemote = remotes:WaitForChild("SelectDragon") :: RemoteEvent
	unlockDragonRemote = remotes:WaitForChild("UnlockDragon") :: RemoteEvent
end

local function refreshCard(dragonId: string)
	local card = dragonCards[dragonId]
	if not card then return end
	local dragon = DragonConfig[dragonId]
	if not dragon then return end

	local isUnlocked = cachedUnlocks[dragonId] == true
	local isSelected = cachedSelected == dragonId
	local canAfford = cachedCoins >= dragon.cost

	-- Card visual state
	if isSelected then
		card.card.BackgroundColor3 = dragon.color
		card.card.BackgroundTransparency = 0.5
		card.status.Text = "EQUIPPED"
		card.status.TextColor3 = Color3.fromRGB(255, 255, 255)
	elseif isUnlocked then
		card.card.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
		card.card.BackgroundTransparency = 0.2
		card.status.Text = "Click to select"
		card.status.TextColor3 = Color3.fromRGB(180, 220, 180)
	elseif canAfford then
		card.card.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
		card.card.BackgroundTransparency = 0.4
		card.status.Text = `Buy: {dragon.cost} coins`
		card.status.TextColor3 = Color3.fromRGB(255, 215, 0)
	else
		card.card.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		card.card.BackgroundTransparency = 0.5
		card.status.Text = `Locked ({dragon.cost} coins)`
		card.status.TextColor3 = Color3.fromRGB(150, 150, 150)
	end
end

local function refreshAllCards()
	for dragonId in dragonCards do
		refreshCard(dragonId)
	end
end

local function buildCard(dragonId: string, parent: Frame): { card: Frame, status: TextLabel }
	local dragon = DragonConfig[dragonId]
	assert(dragon, `Unknown dragon: {dragonId}`)

	local card = Instance.new("Frame")
	card.Name = `Card_{dragonId}`
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	card.BorderSizePixel = 0
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = dragon.color
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card

	-- Color block at top representing the dragon's element color
	local colorBlock = Instance.new("Frame")
	colorBlock.Size = UDim2.new(1, -20, 0, 60)
	colorBlock.Position = UDim2.fromOffset(10, 10)
	colorBlock.BackgroundColor3 = dragon.color
	colorBlock.BorderSizePixel = 0
	colorBlock.Parent = card

	local colorCorner = Instance.new("UICorner")
	colorCorner.CornerRadius = UDim.new(0, 6)
	colorCorner.Parent = colorBlock

	local elementLabel = Instance.new("TextLabel")
	elementLabel.Size = UDim2.fromScale(1, 1)
	elementLabel.BackgroundTransparency = 1
	elementLabel.Text = dragon.element:upper()
	elementLabel.TextColor3 = Color3.new(1, 1, 1)
	elementLabel.TextStrokeTransparency = 0
	elementLabel.Font = Enum.Font.GothamBlack
	elementLabel.TextScaled = true
	elementLabel.Parent = colorBlock

	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -20, 0, 30)
	nameLabel.Position = UDim2.fromOffset(10, 80)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = dragon.name
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.Parent = card

	-- Stats row
	local statsLabel = Instance.new("TextLabel")
	statsLabel.Size = UDim2.new(1, -20, 0, 60)
	statsLabel.Position = UDim2.fromOffset(10, 115)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Text = `HP: {dragon.health}\nSPD: {dragon.speed}  DMG: {dragon.damage}\nSpecial: {dragon.specialName}`
	statsLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
	statsLabel.Font = Enum.Font.Gotham
	statsLabel.TextSize = 12
	statsLabel.TextWrapped = true
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	statsLabel.TextYAlignment = Enum.TextYAlignment.Top
	statsLabel.Parent = card

	-- Status label at bottom (Equipped / Click to select / Buy: X coins / Locked)
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(1, -20, 0, 25)
	status.Position = UDim2.new(0, 10, 1, -35)
	status.BackgroundTransparency = 1
	status.Text = "Locked"
	status.TextColor3 = Color3.fromRGB(150, 150, 150)
	status.Font = Enum.Font.GothamBold
	status.TextSize = 14
	status.Parent = card

	-- Click handler — wraps the whole card in a TextButton overlay
	local clickButton = Instance.new("TextButton")
	clickButton.Size = UDim2.fromScale(1, 1)
	clickButton.BackgroundTransparency = 1
	clickButton.Text = ""
	clickButton.AutoButtonColor = false
	clickButton.Parent = card

	clickButton.Activated:Connect(function()
		local isUnlocked = cachedUnlocks[dragonId] == true
		if isUnlocked then
			-- Select this dragon (server validates ownership)
			if selectDragonRemote then
				selectDragonRemote:FireServer(dragonId)
			end
			cachedSelected = dragonId
			refreshAllCards()
		else
			-- Try to unlock (server validates funds + sends UpdateCoins back)
			if cachedCoins >= dragon.cost then
				if unlockDragonRemote then
					unlockDragonRemote:FireServer(dragonId)
				end
				-- Optimistic UI: show as unlocked immediately. If server rejects,
				-- the next data refresh will undo it.
				cachedUnlocks[dragonId] = true
				cachedCoins -= dragon.cost
				refreshAllCards()
			end
		end
	end)

	return { card = card, status = status }
end

function DragonSelectUI.create()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DragonSelectUI"
	screenGui.Enabled = false
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui

	-- Dimmed backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screenGui

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 60)
	title.Position = UDim2.fromOffset(0, 30)
	title.BackgroundTransparency = 1
	title.Text = "PICK YOUR DRAGON"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.Parent = screenGui

	-- Subtitle (intermission countdown context)
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, 0, 0, 25)
	subtitle.Position = UDim2.fromOffset(0, 90)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Round starts soon..."
	subtitle.TextColor3 = Color3.fromRGB(200, 200, 200)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextScaled = true
	subtitle.Parent = screenGui

	-- Coins display
	local coinsLabel = Instance.new("TextLabel")
	coinsLabel.Name = "Coins"
	coinsLabel.Size = UDim2.fromOffset(200, 40)
	coinsLabel.Position = UDim2.new(0.5, -100, 0, 125)
	coinsLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	coinsLabel.BackgroundTransparency = 0.3
	coinsLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	coinsLabel.Text = "0 coins"
	coinsLabel.Font = Enum.Font.GothamBold
	coinsLabel.TextScaled = true
	coinsLabel.Parent = screenGui

	local coinsCorner = Instance.new("UICorner")
	coinsCorner.CornerRadius = UDim.new(0, 8)
	coinsCorner.Parent = coinsLabel

	-- Grid container: 3 columns × 2 rows
	local gridContainer = Instance.new("Frame")
	gridContainer.Size = UDim2.new(0.85, 0, 0.65, 0)
	gridContainer.Position = UDim2.new(0.5, 0, 0.5, 30)
	gridContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	gridContainer.BackgroundTransparency = 1
	gridContainer.Parent = screenGui

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.32, 0, 0.48, 0)
	grid.CellPadding = UDim2.new(0.01, 0, 0.02, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = gridContainer

	-- Build cards in defined order so the grid layout is deterministic
	for i, dragonId in DRAGON_ORDER do
		local cellWrapper = Instance.new("Frame")
		cellWrapper.Name = `Cell_{dragonId}`
		cellWrapper.BackgroundTransparency = 1
		cellWrapper.LayoutOrder = i
		cellWrapper.Parent = gridContainer

		dragonCards[dragonId] = buildCard(dragonId, cellWrapper)
	end

	-- Footer hint
	local footer = Instance.new("TextLabel")
	footer.Size = UDim2.new(1, 0, 0, 30)
	footer.Position = UDim2.new(0, 0, 1, -50)
	footer.BackgroundTransparency = 1
	footer.Text = "Click a dragon to select. Round starts when timer ends."
	footer.TextColor3 = Color3.fromRGB(200, 200, 200)
	footer.Font = Enum.Font.Gotham
	footer.TextScaled = true
	footer.Parent = screenGui

	refreshAllCards()
end

function DragonSelectUI.show(intermissionSeconds: number?)
	if screenGui then
		screenGui.Enabled = true
		if intermissionSeconds and screenGui:FindFirstChild("Subtitle") then
			(screenGui.Subtitle :: TextLabel).Text = `Round starts in {intermissionSeconds}s...`
		elseif screenGui:FindFirstChild("Subtitle") then
			-- B-key open during a round: no countdown, generic prompt
			(screenGui.Subtitle :: TextLabel).Text = "Pick a dragon — press B to close"
		end
		-- Free the mouse so players can click cards
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		-- Show the gamepad navigation cursor on EVERY open path (B-key,
		-- intermission auto-show, Y-button). Previously the cursor only
		-- appeared when opened via Y → controller users opening via B saw
		-- no cursor until their first D-pad press. Late-bound lookup so
		-- show() can predate the gamepad section's function definition.
		if DragonSelectUI.resetGamepadCursor then
			DragonSelectUI.resetGamepadCursor()
		end
	end
end

function DragonSelectUI.hide()
	if screenGui then
		screenGui.Enabled = false
		-- Re-lock the cursor so combat aim works again. Safe to set even if
		-- caller has different intent — they can override after.
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

function DragonSelectUI.toggle()
	if screenGui then
		if screenGui.Enabled then
			DragonSelectUI.hide()
		else
			DragonSelectUI.show()
		end
	end
end

function DragonSelectUI.isOpen(): boolean
	return screenGui ~= nil and screenGui.Enabled
end

function DragonSelectUI.updateCoins(coins: number)
	cachedCoins = coins
	if screenGui and screenGui:FindFirstChild("Coins") then
		(screenGui.Coins :: TextLabel).Text = `{coins} coins`
	end
	refreshAllCards()
end

function DragonSelectUI.updatePlayerData(data: { coins: number, unlockedDragons: { [string]: boolean }, selectedDragon: string }?)
	if not data then return end
	cachedCoins = data.coins
	cachedUnlocks = data.unlockedDragons
	cachedSelected = data.selectedDragon
	if screenGui and screenGui:FindFirstChild("Coins") then
		(screenGui.Coins :: TextLabel).Text = `{data.coins} coins`
	end
	refreshAllCards()
end

function DragonSelectUI.updateSubtitle(text: string)
	if screenGui and screenGui:FindFirstChild("Subtitle") then
		(screenGui.Subtitle :: TextLabel).Text = text
	end
end

-- ============================================================================
-- GAMEPAD NAVIGATION (PS5/Xbox)
-- ============================================================================
-- The 3-column × 2-row grid maps to D-pad navigation: Up/Down moves rows,
-- Left/Right moves columns. A button = "click this card" (delegates to the
-- same handler the mouse uses). B button = close the menu. Y button = open.
-- The "selected for navigation" cursor is a UIStroke we toggle on/off as the
-- gamepad cursor moves around the grid (separate from the "equipped" stroke
-- that's part of normal card rendering).

local GAMEPAD_COLS = 3
local GAMEPAD_ROWS = 2 -- DRAGON_ORDER has 6 entries; matches grid

-- The cursor index is into DRAGON_ORDER: 1..6. We map back and forth with
-- (col, row) = ((idx-1) % cols + 1, math.floor((idx-1) / cols) + 1).
local cursorIndex = 1
local cursorStroke: UIStroke? = nil

local function applyCursorVisual()
	-- Find the card the cursor should land on. If it doesn't exist yet
	-- (cards built lazily), park the stroke off-tree until it does.
	local dragonId = DRAGON_ORDER[cursorIndex]
	local cardWrap = dragonCards[dragonId]
	if not cardWrap then return end

	-- Create the stroke once on first use; subsequent calls just REPARENT
	-- it to the new card. Avoids the destroy/recreate churn that would
	-- otherwise allocate + GC a UIStroke and trigger a layout pass on
	-- every D-pad press (kids spam navigation).
	if not cursorStroke then
		cursorStroke = Instance.new("UIStroke")
		(cursorStroke :: UIStroke).Name = "GamepadCursor"
		(cursorStroke :: UIStroke).Color = Color3.fromRGB(120, 220, 255) -- distinct cyan vs equipped stroke
		(cursorStroke :: UIStroke).Thickness = 5
	end
	(cursorStroke :: UIStroke).Parent = cardWrap.card
end

local function moveCursor(dx: number, dy: number)
	local col = ((cursorIndex - 1) % GAMEPAD_COLS) + 1
	local row = math.floor((cursorIndex - 1) / GAMEPAD_COLS) + 1
	col = math.clamp(col + dx, 1, GAMEPAD_COLS)
	row = math.clamp(row + dy, 1, GAMEPAD_ROWS)
	cursorIndex = math.clamp((row - 1) * GAMEPAD_COLS + col, 1, #DRAGON_ORDER)
	applyCursorVisual()
end

local function confirmCursorSelection()
	local dragonId = DRAGON_ORDER[cursorIndex]
	if not dragonId then return end
	-- Reuse the existing click handler logic (select if unlocked, buy if affordable)
	local dragon = DragonConfig[dragonId]
	if not dragon then return end
	local isUnlocked = cachedUnlocks[dragonId] == true
	if isUnlocked then
		if selectDragonRemote then selectDragonRemote:FireServer(dragonId) end
		cachedSelected = dragonId
		refreshAllCards()
		applyCursorVisual() -- refresh restored the stroke; reapply cursor on top
	else
		if cachedCoins >= dragon.cost then
			if unlockDragonRemote then unlockDragonRemote:FireServer(dragonId) end
			cachedUnlocks[dragonId] = true
			cachedCoins -= dragon.cost
			refreshAllCards()
			applyCursorVisual()
		end
	end
end

-- Public reset entry point. Called by DragonSelectUI.show() on every open
-- path (B-key, Y-button, intermission auto-open) so the gamepad cursor
-- becomes visible immediately rather than after the player's first D-pad
-- press. Defined here (not at module top) because it depends on the local
-- applyCursorVisual closure; show() looks it up late on the table.
function DragonSelectUI.resetGamepadCursor()
	cursorIndex = 1
	applyCursorVisual()
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	-- Y / Triangle: open menu mid-round (toggleable). Always responsive
	-- regardless of menu state, like a pause button. Cursor reset is now
	-- handled inside DragonSelectUI.show(), so we just toggle here.
	if input.KeyCode == Enum.KeyCode.ButtonY then
		DragonSelectUI.toggle()
		return
	end

	-- All other gamepad bindings only matter while the menu is open.
	if not DragonSelectUI.isOpen() then return end
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.DPadLeft then moveCursor(-1, 0) end
	if input.KeyCode == Enum.KeyCode.DPadRight then moveCursor(1, 0) end
	if input.KeyCode == Enum.KeyCode.DPadUp then moveCursor(0, -1) end
	if input.KeyCode == Enum.KeyCode.DPadDown then moveCursor(0, 1) end
	if input.KeyCode == Enum.KeyCode.ButtonA then confirmCursorSelection() end
	if input.KeyCode == Enum.KeyCode.ButtonB then DragonSelectUI.hide() end
end)

return DragonSelectUI
