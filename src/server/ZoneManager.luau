--!strict
-- Sprint 5 Part C: server-authoritative zone tracking.
--
-- Tells the rest of the game "is this player/position currently in the Lair?"
-- so combat code (CombatManager, NPCManager) can refuse to deal damage to
-- safe-zone players. Until this module landed, the Lair was "safe by accident"
-- because the spatial separation (Lair Y=500, Arena Y=50, NPC detection range
-- ~150 studs) kept threats away. This makes the rule explicit so we can't
-- regress later when a Boss with bigger range or a fast-moving NPC ships.
--
-- Two interfaces:
--   - isPlayerInLair / isPositionInLair: synchronous spatial test, real-time.
--     Used by combat hot paths so they get a fresh answer every call without
--     waiting on the tick loop.
--   - Player:GetAttribute("Zone"): updated ~5Hz by the tracking loop. Clients
--     read this for UI ("Safe Zone" indicator) and listen via
--     GetAttributeChangedSignal. We use an attribute (not a remote event)
--     because Roblox replicates attributes automatically and this avoids a
--     new RemoteEvent for what is effectively per-player state.
--
-- The Lair zone is a sphere centered on LairBuilder.LAIR_CENTER with radius
-- LAIR_RADIUS. A sphere is enough: the Arena is 2000 studs away, so even a
-- player flying straight up from Arena origin to Y=500 is still far outside
-- the Lair sphere.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LairBuilder = require(script.Parent.LairBuilder)

local ZoneManager = {}

-- Lair sphere radius. Sized to comfortably enclose:
--   - the floor disc (FLOOR_RADIUS = 100)
--   - the portal disc (sits at z=70 from center)
--   - generous Y margin so flying around the Lair never accidentally
--     "exits" the safe zone and gets you targeted by a stray NPC
-- 180 leaves ~80 studs of cushion past the visible Lair geometry.
local LAIR_RADIUS = 180
local LAIR_RADIUS_SQ = LAIR_RADIUS * LAIR_RADIUS

local TICK_RATE = 0.2 -- 5Hz; zone changes are infrequent so this is plenty

-- Zone label values (kept as plain strings since Player:GetAttribute uses Variant).
local ZONE_LAIR = "Lair"
local ZONE_ARENA = "Arena"

ZoneManager.ZONE_LAIR = ZONE_LAIR
ZoneManager.ZONE_ARENA = ZONE_ARENA

function ZoneManager.isPositionInLair(pos: Vector3): boolean
	-- Squared-distance compare to skip the sqrt — this runs on every combat
	-- hit-detection call so the tiny perf win adds up.
	local d = pos - LairBuilder.LAIR_CENTER
	return (d.X * d.X + d.Y * d.Y + d.Z * d.Z) < LAIR_RADIUS_SQ
end

function ZoneManager.isPlayerInLair(player: Player): boolean
	local character = player.Character
	if not character or not character.PrimaryPart then
		-- No character yet (just-joined, mid-respawn): treat as Lair so we
		-- never accidentally apply damage to a player without a body. This is
		-- the safer failure mode — the alternative ("treat as Arena") could
		-- damage someone whose character is being rebuilt.
		return true
	end
	return ZoneManager.isPositionInLair(character.PrimaryPart.Position)
end

-- Start the per-player zone-attribute update loop. Called once from
-- init.server.luau after build. Sets Player:GetAttribute("Zone") to "Lair"
-- or "Arena" so clients can drive their Safe-Zone UI without a remote.
local started = false
function ZoneManager.startTracking()
	if started then return end
	started = true

	-- Initial pass on join so the attribute exists immediately. Clients
	-- listening via GetAttributeChangedSignal won't get a "first" event
	-- otherwise and the Safe-Zone label could miss the initial state.
	Players.PlayerAdded:Connect(function(player: Player)
		player:SetAttribute("Zone", ZONE_LAIR)
	end)
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Zone") == nil then
			player:SetAttribute("Zone", ZONE_LAIR)
		end
	end

	task.spawn(function()
		while true do
			task.wait(TICK_RATE)
			-- Per-iteration pcall so a transient error (e.g. character mid-rebuild)
			-- doesn't break zone tracking for the entire server lifetime.
			-- Failure here is rare enough to log without rate-limiting.
			local ok, err = pcall(function()
				for _, player in Players:GetPlayers() do
					local newZone = if ZoneManager.isPlayerInLair(player) then ZONE_LAIR else ZONE_ARENA
					if player:GetAttribute("Zone") ~= newZone then
						player:SetAttribute("Zone", newZone)
					end
				end
			end)
			if not ok then
				warn(`[ZoneManager] tick error: {err}`)
			end
		end
	end)
end

return ZoneManager
