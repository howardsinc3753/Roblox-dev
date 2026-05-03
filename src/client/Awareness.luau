--!strict
-- Awareness HUD: helps kids find enemies and react to incoming damage.
--
-- Two systems share this module because they both rely on the same
-- world-position → screen-edge projection math:
--
--   1. Damage Direction Indicator: red arc flashes on the screen edge in the
--      direction of the player who just hit you. Fades over ~1.5s. Multiple
--      indicators stack (so you can tell two enemies are flanking you).
--
--   2. Compass Arrows: small triangles on the screen edge pointing toward the
--      nearest 5 enemies/NPCs that are off-screen. Updated every frame so
--      they track movement. Color-coded by entity type.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Awareness = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local camera = workspace.CurrentCamera

-- Layout constants. Tuned for 1920x1080 baseline; UDim2.fromScale handles
-- proportional scaling for other resolutions.
local EDGE_PADDING = 50 -- pixels from screen edge to the indicator
local COMPASS_TRIANGLE_SIZE = 44 -- bigger so kids actually notice it on screen edge
local DAMAGE_ARC_SIZE = 80
local DAMAGE_FADE_DURATION = 1.5 -- seconds
local MAX_COMPASS_TRACKED = 5 -- show closest N off-screen entities
local COMPASS_NPC_TAG = "DragonWarz_NPC"

local screenGui: ScreenGui
local compassContainer: Frame
local damageContainer: Frame

-- Per-arrow state for compass: maps entity ID (player.UserId or npc model.GUID)
-- to the ImageLabel/Frame so we can update existing ones instead of recreating
-- them every frame (avoids GC churn).
local compassArrows: { [string]: Frame } = {}
local compassUsedThisFrame: { [string]: boolean } = {}

function Awareness.create()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "Awareness"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 5 -- above HUD, below modals
	screenGui.Parent = playerGui

	-- Two layers so damage flashes don't z-fight with compass arrows
	compassContainer = Instance.new("Frame")
	compassContainer.Name = "Compass"
	compassContainer.Size = UDim2.fromScale(1, 1)
	compassContainer.BackgroundTransparency = 1
	compassContainer.Parent = screenGui

	damageContainer = Instance.new("Frame")
	damageContainer.Name = "DamageIndicators"
	damageContainer.Size = UDim2.fromScale(1, 1)
	damageContainer.BackgroundTransparency = 1
	damageContainer.Parent = screenGui
end

-- Project a world position to the screen-edge intersection of the line from
-- screen-center to the entity's screen position. Used for both off-screen
-- compass arrows AND damage-direction arcs.
-- Returns (edgeX, edgeY, angle) — angle in radians, 0 = right, math.pi/2 = down
local function projectToScreenEdge(worldPos: Vector3): (number, number, number)
	local viewSize = camera.ViewportSize
	local centerX = viewSize.X / 2
	local centerY = viewSize.Y / 2

	-- Camera's relative direction to target. We use yaw only (XZ plane) so
	-- "above/below" doesn't tilt the indicator vertically — kids would find
	-- that confusing.
	local cameraCF = camera.CFrame
	local localPlayerPos = (player.Character and player.Character.PrimaryPart)
		and player.Character.PrimaryPart.Position
		or cameraCF.Position
	local toTarget = worldPos - localPlayerPos

	-- Yaw of the camera (where it's looking on the XZ plane)
	local cameraLook = cameraCF.LookVector
	local cameraYaw = math.atan2(-cameraLook.X, -cameraLook.Z)
	-- Yaw of the target direction relative to the local player
	local targetYaw = math.atan2(-toTarget.X, -toTarget.Z)
	-- Relative angle: 0 = directly in front, +PI/2 = right, -PI/2 = left
	local relativeAngle = targetYaw - cameraYaw
	-- Normalize to [-PI, PI]
	while relativeAngle > math.pi do relativeAngle -= math.pi * 2 end
	while relativeAngle < -math.pi do relativeAngle += math.pi * 2 end

	-- Convert to screen-edge position: 0 rad → top of screen, +PI/2 → right,
	-- ±PI → bottom, -PI/2 → left. This maps "where in 3D space" to "where on
	-- the 2D HUD edge" the indicator should appear.
	-- We use (sin, -cos) so rad=0 maps to (0, -1) = top.
	local dirX = math.sin(relativeAngle)
	local dirY = -math.cos(relativeAngle)

	-- Find where this direction vector hits the screen edge rectangle.
	-- The edge rectangle is [centerX - halfW, centerX + halfW] horizontally
	-- and similar vertically, with EDGE_PADDING inset.
	local halfW = centerX - EDGE_PADDING
	local halfH = centerY - EDGE_PADDING
	-- Scale the direction vector so it hits the rectangle. Whichever axis
	-- saturates first (|dirX|/halfW or |dirY|/halfH) determines the scale.
	local scale = math.huge
	if dirX ~= 0 then scale = math.min(scale, halfW / math.abs(dirX)) end
	if dirY ~= 0 then scale = math.min(scale, halfH / math.abs(dirY)) end
	if scale == math.huge then scale = halfW end -- shouldn't happen but safe

	local edgeX = centerX + dirX * scale
	local edgeY = centerY + dirY * scale
	-- The icon's rotation: triangle points outward (away from screen center).
	-- atan2(dirY, dirX) gives the angle of the position vector. Add 90° because
	-- our triangle asset points UP by default (negative Y direction).
	local rotation = math.deg(math.atan2(dirY, dirX)) + 90

	return edgeX, edgeY, rotation
end

-- ================================
-- DAMAGE DIRECTION INDICATOR
-- ================================

-- Shows a red arc pointing toward damage source. Multiple can stack.
-- Called from init.client.luau when local player takes damage.
function Awareness.showDamageFrom(sourcePos: Vector3)
	if not damageContainer then return end

	-- Frame instead of an image so we don't depend on uploaded assets.
	-- A red semi-transparent frame with a pointed top (UICorner + rotation)
	-- reads as "incoming damage from this direction" once it appears + fades.
	local arc = Instance.new("Frame")
	arc.Size = UDim2.fromOffset(DAMAGE_ARC_SIZE, DAMAGE_ARC_SIZE * 0.4)
	arc.BackgroundColor3 = Color3.fromRGB(255, 30, 30)
	arc.BorderSizePixel = 0
	arc.AnchorPoint = Vector2.new(0.5, 0.5)
	arc.Parent = damageContainer

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = arc

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = arc

	-- Position + rotate based on the world position
	local function update()
		local x, y, rot = projectToScreenEdge(sourcePos)
		arc.Position = UDim2.fromOffset(x, y)
		arc.Rotation = rot
	end
	update()

	-- Track-while-fading: re-aim every frame for the first 0.5s so a moving
	-- attacker doesn't leave a stale indicator pointing at where they were.
	local startTick = tick()
	local trackConn: RBXScriptConnection
	trackConn = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTick
		if elapsed >= DAMAGE_FADE_DURATION then
			trackConn:Disconnect()
			arc:Destroy()
			return
		end
		-- Track for first 33% of the fade window; freeze position after
		if elapsed < DAMAGE_FADE_DURATION * 0.33 then
			update()
		end
		local fadeProgress = elapsed / DAMAGE_FADE_DURATION
		arc.BackgroundTransparency = fadeProgress
		stroke.Transparency = 0.3 + fadeProgress * 0.7
	end)
end

-- ================================
-- COMPASS ARROWS (off-screen entities)
-- ================================

-- Returns true if the world position is on-screen and in front of the camera
local function isOnScreen(worldPos: Vector3): boolean
	local screenPoint, onScreen = camera:WorldToViewportPoint(worldPos)
	if not onScreen then return false end
	-- Roblox's onScreen returns true for behind-camera with negative Z too
	return screenPoint.Z > 0
end

-- Build or reuse a compass arrow for a given entity ID. Uses a TextLabel
-- with the ▲ unicode character so it actually LOOKS like an arrow when
-- rotated, instead of the previous "rotated rounded square" that read as
-- a colored dot. The text strokes give it readability against any
-- background; the colored fill identifies entity type at a glance.
local function getOrCreateArrow(entityId: string, color: Color3): Frame
	local arrow = compassArrows[entityId]
	if arrow then
		return arrow
	end

	-- Outer Frame is the rotation target. The ▲ TextLabel inside renders
	-- the arrow shape; rotating the Frame rotates the whole thing.
	local frame = Instance.new("Frame")
	frame.Name = `Arrow_{entityId}`
	frame.Size = UDim2.fromOffset(COMPASS_TRIANGLE_SIZE, COMPASS_TRIANGLE_SIZE)
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Parent = compassContainer

	local label = Instance.new("TextLabel")
	label.Name = "Glyph"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "▲" -- points up by default; matches rotation=0 = "ahead of you"
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = frame

	compassArrows[entityId] = frame
	return frame
end

-- Per-frame compass update. Called from init.client.luau Heartbeat.
function Awareness.updateCompass()
	if not compassContainer then return end

	local localChar = player.Character
	if not localChar or not localChar.PrimaryPart then
		-- Hide all arrows if local player has no character
		for _, arrow in compassArrows do
			arrow.Visible = false
		end
		return
	end
	local localPos = localChar.PrimaryPart.Position

	-- Reset frame-usage tracker. After processing, anything not marked used
	-- gets hidden (entity may have died or moved on-screen since last frame).
	table.clear(compassUsedThisFrame)

	-- Collect candidate entities with their distances. Cheaper to allocate
	-- once and sort than to maintain a heap for ~10 entities.
	type Candidate = { id: string, position: Vector3, color: Color3, distance: number }
	local candidates: { Candidate } = {}

	-- Other players (red, brightest)
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player and otherPlayer.Character and otherPlayer.Character.PrimaryPart then
			local pos = otherPlayer.Character.PrimaryPart.Position
			table.insert(candidates, {
				id = `player_{otherPlayer.UserId}`,
				position = pos,
				color = Color3.fromRGB(255, 50, 50),
				distance = (pos - localPos).Magnitude,
			})
		end
	end

	-- NPCs (orange — distinct color so kids can tell players apart from bots)
	for _, npcModel in CollectionService:GetTagged(COMPASS_NPC_TAG) do
		local model = npcModel :: Model
		if model.PrimaryPart and model.Parent then
			local pos = model.PrimaryPart.Position
			table.insert(candidates, {
				id = `npc_{model:GetDebugId()}`,
				position = pos,
				color = Color3.fromRGB(255, 140, 0),
				distance = (pos - localPos).Magnitude,
			})
		end
	end

	-- Sort by distance, take closest N
	table.sort(candidates, function(a, b) return a.distance < b.distance end)
	local shown = math.min(#candidates, MAX_COMPASS_TRACKED)

	-- Render arrows for off-screen entities only
	for i = 1, shown do
		local c = candidates[i]
		if not isOnScreen(c.position) then
			local arrow = getOrCreateArrow(c.id, c.color)
			local x, y, rot = projectToScreenEdge(c.position)
			arrow.Position = UDim2.fromOffset(x, y)
			arrow.Rotation = rot
			arrow.Visible = true
			compassUsedThisFrame[c.id] = true
		end
	end

	-- Hide arrows for entities not used this frame (on-screen, dead, or beyond top-N)
	for entityId, arrow in compassArrows do
		if not compassUsedThisFrame[entityId] then
			arrow.Visible = false
		end
	end

	-- GC sweep: if an arrow has been hidden for many frames AND its entity is
	-- gone, destroy it to keep the table from growing unboundedly. Cheap
	-- enough to do every frame given the small N.
	for entityId, arrow in compassArrows do
		if not arrow.Visible and (entityId:sub(1, 4) == "npc_") then
			-- NPC arrows: check if any candidate matches; if not, the NPC died
			local stillExists = false
			for _, c in candidates do
				if c.id == entityId then stillExists = true; break end
			end
			if not stillExists then
				arrow:Destroy()
				compassArrows[entityId] = nil
			end
		end
	end
end

return Awareness
