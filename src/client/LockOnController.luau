--!strict
-- Soft lock-on targeting for casual aerial combat.
--
-- F key cycles through enemies (other players + NPCs) in the forward cone
-- within range. A bracket reticle appears on the locked target. Lock breaks
-- automatically when target dies/despawns, leaves the cone, or moves out of
-- range — no manual cleanup needed.
--
-- The CombatInput module reads the current lock via getLockedTarget() and
-- biases breath direction toward the locked target. Lock-on is purely
-- client-side state (no server roundtrip) — server still validates the
-- final breath direction with its own cone test, so this just makes aim
-- more forgiving without bypassing authority.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LockOnController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local camera = workspace.CurrentCamera

-- Optional: fires LockOnTarget remote so server can warn the locked player.
-- Resolved lazily because the remote folder may not exist when this module
-- loads (depends on require order). Caches once found.
local lockOnTargetRemote: RemoteEvent? = nil
local function getLockOnRemote(): RemoteEvent?
	if lockOnTargetRemote then return lockOnTargetRemote end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		lockOnTargetRemote = remotes:FindFirstChild("LockOnTarget") :: RemoteEvent?
	end
	return lockOnTargetRemote
end

-- Track the last userId we reported to server. Avoids re-firing the remote
-- every frame when the lock state hasn't changed.
local lastReportedUserId = 0

-- Tuning. The lock cone is wider than the breath cone so lock-on is more
-- permissive than aim — you can lock something to your side, then the aim
-- assist pulls your breath toward it on fire.
local LOCK_RANGE = 300 -- studs; covers full arena (NPCs spawn at radius 250)
local LOCK_CONE_DOT = 0.5 -- ~60 deg half-angle = 120 deg cone
local NPC_TAG = "DragonWarz_NPC"
local RETICLE_FILL_COLOR = Color3.fromRGB(255, 80, 80)
local RETICLE_OUTLINE_COLOR = Color3.fromRGB(255, 220, 80)

export type LockTarget = {
	kind: string, -- "player" | "npc"
	userId: number?, -- for player kind only
	model: Model,
	rootPart: BasePart,
}

local currentTarget: LockTarget? = nil
-- Lock visual = Highlight (bright outline around target's whole model) +
-- BillboardGui (small "TARGET" label above target). Highlight is Roblox's
-- newer primitive specifically for "this thing is selected/highlighted" —
-- much more visible than corner-bracket BillboardGuis at distance.
local highlight: Highlight? = nil
local labelGui: BillboardGui? = nil

-- Build the lock visual once. Two pieces:
--   1. Highlight — Roblox's "this whole model is selected" outline. Visible
--      from any angle/distance, doesn't need to be sized in studs/pixels.
--   2. BillboardGui label "▼ TARGET" hovering above the target. Small,
--      sized in pixels (Offset on BillboardGui *children* IS pixels even
--      though the BillboardGui itself sizes in studs).
local function ensureReticle()
	if highlight and labelGui then return end

	highlight = Instance.new("Highlight")
	highlight.Name = "LockOnHighlight"
	highlight.FillColor = RETICLE_FILL_COLOR
	highlight.OutlineColor = RETICLE_OUTLINE_COLOR
	highlight.FillTransparency = 0.6 -- partial fill so the dragon mesh stays visible
	highlight.OutlineTransparency = 0 -- solid outline = unmistakable
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- visible through walls
	highlight.Enabled = false
	highlight.Parent = playerGui

	labelGui = Instance.new("BillboardGui")
	labelGui.Name = "LockOnLabel"
	labelGui.Size = UDim2.fromOffset(150, 40) -- 150x40 STUDS in 3D — Roblox auto-scales by distance
	labelGui.StudsOffset = Vector3.new(0, 8, 0) -- float above the target
	labelGui.AlwaysOnTop = true
	labelGui.LightInfluence = 0
	labelGui.Enabled = false
	labelGui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "▼ LOCKED ▼"
	label.TextColor3 = RETICLE_FILL_COLOR
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = labelGui
end

-- Tell server about lock state change. Server forwards a LockedByEnemy
-- event to the targeted player so they get the warning flash. Sends 0
-- when unlocking (or when lock is on an NPC, since NPCs don't get warnings).
local function reportLockToServer(userId: number)
	if userId == lastReportedUserId then return end
	lastReportedUserId = userId
	local remote = getLockOnRemote()
	if remote then
		remote:FireServer(userId)
	end
end

local function clearLock()
	currentTarget = nil
	if highlight then
		highlight.Enabled = false
		highlight.Adornee = nil
	end
	if labelGui then
		labelGui.Enabled = false
		labelGui.Adornee = nil
	end
	reportLockToServer(0)
end

local function setLock(target: LockTarget)
	currentTarget = target
	if highlight then
		highlight.Adornee = target.model -- Highlight wraps the whole model, not just rootPart
		highlight.Enabled = true
	end
	if labelGui then
		labelGui.Adornee = target.rootPart
		labelGui.Enabled = true
	end
	-- Only player locks generate cross-client warnings (NPCs can't be alerted)
	if target.kind == "player" and target.userId then
		reportLockToServer(target.userId)
	else
		reportLockToServer(0)
	end
end

-- Compare two targets for equality. Used during cycle to detect "current".
local function targetsEqual(a: LockTarget, b: LockTarget): boolean
	if a.kind ~= b.kind then return false end
	if a.kind == "player" then
		return a.userId == b.userId
	else
		return a.model == b.model
	end
end

-- Build a list of valid lock candidates: alive players + NPCs within cone
-- and range, sorted by distance ascending. Used by Tab/cycle handler.
local function findCandidates(): { LockTarget }
	local localChar = player.Character
	if not localChar or not localChar.PrimaryPart then return {} end
	local origin = localChar.PrimaryPart.Position
	local forward = camera.CFrame.LookVector

	type Candidate = { target: LockTarget, distance: number }
	local list: { Candidate } = {}

	-- Other players
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player and otherPlayer.Character and otherPlayer.Character.PrimaryPart then
			local pos = otherPlayer.Character.PrimaryPart.Position
			local toTarget = pos - origin
			local dist = toTarget.Magnitude
			if dist > 0 and dist <= LOCK_RANGE then
				local dot = toTarget.Unit:Dot(forward)
				if dot >= LOCK_CONE_DOT then
					table.insert(list, {
						target = {
							kind = "player",
							userId = otherPlayer.UserId,
							model = otherPlayer.Character,
							rootPart = otherPlayer.Character.PrimaryPart :: BasePart,
						},
						distance = dist,
					})
				end
			end
		end
	end

	-- NPCs (any tagged DragonWarz_NPC)
	for _, npcModel in CollectionService:GetTagged(NPC_TAG) do
		local model = npcModel :: Model
		if model.Parent and model.PrimaryPart then
			local pos = model.PrimaryPart.Position
			local toTarget = pos - origin
			local dist = toTarget.Magnitude
			if dist > 0 and dist <= LOCK_RANGE then
				local dot = toTarget.Unit:Dot(forward)
				if dot >= LOCK_CONE_DOT then
					table.insert(list, {
						target = {
							kind = "npc",
							userId = nil,
							model = model,
							rootPart = model.PrimaryPart,
						},
						distance = dist,
					})
				end
			end
		end
	end

	table.sort(list, function(a, b) return a.distance < b.distance end)
	local result: { LockTarget } = {}
	for _, c in list do
		table.insert(result, c.target)
	end
	return result
end

-- F key handler: cycle through candidates. No-lock + press = lock nearest.
-- Locked + press = cycle to next nearest. No candidates = unlock.
function LockOnController.onLockKeyPressed()
	local candidates = findCandidates()
	-- Diagnostic: confirms F handler ran AND tells us if candidates exist.
	-- Without this it's impossible to tell whether F did nothing because
	-- the input wasn't received vs. because no enemies were in cone+range.
	print(`[LockOn] F pressed. Candidates in cone+range: {#candidates}`)
	if #candidates == 0 then
		clearLock()
		return
	end

	if not currentTarget then
		setLock(candidates[1])
		print(`[LockOn] Locked onto {candidates[1].kind}`)
		return
	end

	-- Find current target in candidate list, jump to next (wrap around)
	local currentIdx: number? = nil
	for i, c in candidates do
		if targetsEqual(c, currentTarget) then
			currentIdx = i
			break
		end
	end

	local nextIdx = if currentIdx then (currentIdx % #candidates) + 1 else 1
	setLock(candidates[nextIdx])
end

function LockOnController.getLockedTarget(): LockTarget?
	return currentTarget
end

-- Per-frame validity check called from init.client.luau Heartbeat.
-- Cheap (~1ms) since we only do work when there's an active lock.
function LockOnController.update()
	if not currentTarget then return end

	local localChar = player.Character
	if not localChar or not localChar.PrimaryPart then
		clearLock()
		return
	end

	-- Validate target still exists
	if currentTarget.kind == "player" then
		local target = Players:GetPlayerByUserId(currentTarget.userId :: number)
		if not target or not target.Character or not target.Character.PrimaryPart then
			clearLock()
			return
		end
		-- Player respawned or switched dragons → re-point reticle to new model
		if currentTarget.model ~= target.Character then
			currentTarget.model = target.Character
			currentTarget.rootPart = target.Character.PrimaryPart :: BasePart
			if reticleGui then reticleGui.Adornee = currentTarget.rootPart end
		end
	elseif currentTarget.kind == "npc" then
		if not currentTarget.model.Parent or not currentTarget.model.PrimaryPart then
			clearLock() -- NPC despawned (killed or arena reset)
			return
		end
	end

	-- Validate still in cone + range
	local origin = localChar.PrimaryPart.Position
	local forward = camera.CFrame.LookVector
	local toTarget = currentTarget.rootPart.Position - origin
	local dist = toTarget.Magnitude
	if dist > LOCK_RANGE then
		clearLock()
		return
	end
	if toTarget.Magnitude > 0.001 then
		local dot = toTarget.Unit:Dot(forward)
		if dot < LOCK_CONE_DOT then
			clearLock()
			return
		end
	end
end

function LockOnController.init()
	ensureReticle()
	print("[LockOn] Initialized. Press F to lock nearest enemy.")
end

return LockOnController
