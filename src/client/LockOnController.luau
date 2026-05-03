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

local LockOnController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local camera = workspace.CurrentCamera

-- Tuning. The lock cone is wider than the breath cone so lock-on is more
-- permissive than aim — you can lock something to your side, then the aim
-- assist pulls your breath toward it on fire.
local LOCK_RANGE = 150 -- studs
local LOCK_CONE_DOT = 0.5 -- ~60 deg half-angle = 120 deg cone
local NPC_TAG = "DragonWarz_NPC"
local RETICLE_COLOR = Color3.fromRGB(255, 80, 80)
local RETICLE_SIZE_PIXELS = 120
local RETICLE_BRACKET_SIZE = 22
local RETICLE_BRACKET_THICKNESS = 3

export type LockTarget = {
	kind: string, -- "player" | "npc"
	userId: number?, -- for player kind only
	model: Model,
	rootPart: BasePart,
}

local currentTarget: LockTarget? = nil
local reticleGui: BillboardGui? = nil

-- Build the bracket-style reticle once. Reused by re-pointing its Adornee.
-- Four L-brackets at the corners of a square, classic lock-on style. Cheap
-- to render (8 frames) and reads instantly as "this thing is targeted".
local function ensureReticle()
	if reticleGui then return end
	reticleGui = Instance.new("BillboardGui")
	reticleGui.Name = "LockOnReticle"
	reticleGui.Size = UDim2.fromOffset(RETICLE_SIZE_PIXELS, RETICLE_SIZE_PIXELS)
	reticleGui.AlwaysOnTop = true
	reticleGui.Enabled = false
	reticleGui.Parent = playerGui

	local function makeBracketStroke(width: number, height: number, posX: UDim, posY: UDim)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(width, height)
		frame.Position = UDim2.new(posX.Scale, posX.Offset, posY.Scale, posY.Offset)
		frame.BackgroundColor3 = RETICLE_COLOR
		frame.BorderSizePixel = 0
		frame.Parent = reticleGui
	end

	-- Each corner = one horizontal stroke + one vertical stroke
	-- Top-left
	makeBracketStroke(RETICLE_BRACKET_SIZE, RETICLE_BRACKET_THICKNESS, UDim.new(0, 0), UDim.new(0, 0))
	makeBracketStroke(RETICLE_BRACKET_THICKNESS, RETICLE_BRACKET_SIZE, UDim.new(0, 0), UDim.new(0, 0))
	-- Top-right
	makeBracketStroke(RETICLE_BRACKET_SIZE, RETICLE_BRACKET_THICKNESS, UDim.new(1, -RETICLE_BRACKET_SIZE), UDim.new(0, 0))
	makeBracketStroke(RETICLE_BRACKET_THICKNESS, RETICLE_BRACKET_SIZE, UDim.new(1, -RETICLE_BRACKET_THICKNESS), UDim.new(0, 0))
	-- Bottom-left
	makeBracketStroke(RETICLE_BRACKET_SIZE, RETICLE_BRACKET_THICKNESS, UDim.new(0, 0), UDim.new(1, -RETICLE_BRACKET_THICKNESS))
	makeBracketStroke(RETICLE_BRACKET_THICKNESS, RETICLE_BRACKET_SIZE, UDim.new(0, 0), UDim.new(1, -RETICLE_BRACKET_SIZE))
	-- Bottom-right
	makeBracketStroke(RETICLE_BRACKET_SIZE, RETICLE_BRACKET_THICKNESS, UDim.new(1, -RETICLE_BRACKET_SIZE), UDim.new(1, -RETICLE_BRACKET_THICKNESS))
	makeBracketStroke(RETICLE_BRACKET_THICKNESS, RETICLE_BRACKET_SIZE, UDim.new(1, -RETICLE_BRACKET_THICKNESS), UDim.new(1, -RETICLE_BRACKET_SIZE))
end

local function clearLock()
	currentTarget = nil
	if reticleGui then
		reticleGui.Enabled = false
		reticleGui.Adornee = nil
	end
end

local function setLock(target: LockTarget)
	currentTarget = target
	if reticleGui then
		reticleGui.Adornee = target.rootPart
		reticleGui.Enabled = true
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
	if #candidates == 0 then
		clearLock()
		return
	end

	if not currentTarget then
		setLock(candidates[1])
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
end

return LockOnController
