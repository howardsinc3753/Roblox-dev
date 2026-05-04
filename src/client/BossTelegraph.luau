--!strict
-- Sprint 10: client-side renderer for Mega Boss attack telegraphs.
--
-- When BLAZE THE INFERNO LORD winds up an attack, the server fires
-- the BossTelegraph remote with attackType + position + duration.
-- This module renders the appropriate ground/world marker so kids see
-- where the hit will land and have time to dodge:
--   InfernoSlam → red translucent circle on the ground at originPos,
--                 expanding from 80% to 100% radius over windupSec
--                 seconds, then fades + collapses. The expansion
--                 telegraphs "this is coming" — kids on Xbox at couch
--                 distance need >1s to react (peer audit guidance,
--                 wind-up tuned to 1.8s).
--   MagmaBeam   → red translucent line/box from originPos along
--                 direction for ~80 studs. Pulses ~3 times during
--                 windupSec then fires the actual beam. Wider than the
--                 server's lethal hitbox so the kid has dodging
--                 confidence (the visual is forgiving; the damage
--                 cone is tighter).
--
-- Damage application is server-authoritative — this module only
-- visualizes. The server applies damage at windup-end via
-- BossManager (commit 4) regardless of what the client renders.
--
-- Self-contained module: creates its own Parts in workspace, cleans
-- them up on tween completion. No HUD/ScreenGui involvement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local BossTelegraph = {}

-- ===== Inferno Slam (red expanding circle on the ground) =====
local function renderSlam(originPos: Vector3, radius: number, windupSec: number)
	-- Anchored cylinder lying flat on the ground, expanding outward.
	-- Spawn at 80% radius so the initial shape is already visible (a
	-- 0% start would pop into existence); grows to 100% over windupSec
	-- so the visual reads as "danger zone closing in."
	local marker = Instance.new("Part")
	marker.Name = "BlazeSlamTelegraph"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.5, radius * 1.6, radius * 1.6) -- 80% diameter at start
	-- Cylinder lays flat (Y axis = up) by rotating 90° on Z. Position
	-- juuust above the ground so it z-fights nothing.
	marker.CFrame = CFrame.new(originPos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	marker.Color = Color3.fromRGB(220, 30, 20)
	marker.Material = Enum.Material.Neon
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 0.4
	marker.Parent = workspace

	-- Expansion tween: grow to full radius over the windup window.
	local growTween = TweenService:Create(marker,
		TweenInfo.new(windupSec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(0.5, radius * 2, radius * 2),
			Transparency = 0.15, -- darken as the danger approaches
		}
	)
	growTween:Play()

	-- Cleanup: marker fades out 0.3s after the windup ends so the kid
	-- sees the "bang" moment before the visual disappears.
	Debris:AddItem(marker, windupSec + 0.3)
	-- After the windup, do a quick fade-out so the marker doesn't
	-- snap-disappear (Roblox Debris removal is instant).
	task.delay(windupSec, function()
		if not marker.Parent then return end
		local fadeOut = TweenService:Create(marker,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Transparency = 1 }
		)
		fadeOut:Play()
	end)
end

-- ===== Magma Beam (red line preview from origin in a direction) =====
local function renderBeam(originPos: Vector3, direction: Vector3, windupSec: number)
	-- Long thin neon block stretching from origin along direction.
	-- Width tuned to be visually obvious from a distance + slightly
	-- wider than the server's lethal hitbox (peer guidance — the
	-- visual is forgiving so kids feel confident dodging).
	local BEAM_LENGTH = 80
	local BEAM_WIDTH = 4
	if direction.Magnitude < 0.001 then return end
	local dirUnit = direction.Unit
	local beamCenter = originPos + dirUnit * (BEAM_LENGTH / 2)

	local marker = Instance.new("Part")
	marker.Name = "BlazeBeamTelegraph"
	marker.Size = Vector3.new(BEAM_WIDTH, BEAM_WIDTH, BEAM_LENGTH)
	-- Orient so Z-axis aligns with dirUnit (lookAt + length-along-Z).
	marker.CFrame = CFrame.lookAt(beamCenter, beamCenter + dirUnit)
	marker.Color = Color3.fromRGB(255, 60, 30)
	marker.Material = Enum.Material.Neon
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 0.5
	marker.Parent = workspace

	-- Pulse 3× during the windup so the kid sees the rhythm of the
	-- impending beam. 0.5s on / 0.5s off pattern would be 3 pulses
	-- in 1.5s (Magma Beam's windup). Loop tween with 6 alternations.
	local pulseUp = TweenService:Create(marker,
		TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 5, true, 0),
		{ Transparency = 0.2 }
	)
	pulseUp:Play()

	Debris:AddItem(marker, windupSec + 0.3)
	task.delay(windupSec, function()
		if not marker.Parent then return end
		-- "Beam fires" moment: brief flash to bright + thicken, then fade
		local fire = TweenService:Create(marker,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 0, Size = Vector3.new(BEAM_WIDTH * 1.5, BEAM_WIDTH * 1.5, BEAM_LENGTH) }
		)
		fire:Play()
		fire.Completed:Connect(function()
			if not marker.Parent then return end
			local fadeOut = TweenService:Create(marker,
				TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Transparency = 1 }
			)
			fadeOut:Play()
		end)
	end)
end

-- ===== Public init: subscribes to the BossTelegraph remote =====
function BossTelegraph.init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	if not remotes then
		warn("[BossTelegraph] No Remotes folder; aborting init")
		return
	end
	local remote = remotes:WaitForChild("BossTelegraph", 10) :: RemoteEvent?
	if not remote then
		warn("[BossTelegraph] BossTelegraph remote missing; aborting init")
		return
	end

	remote.OnClientEvent:Connect(function(attackType: string, originPos: Vector3, directionOrRadius: Vector3, windupSec: number)
		-- Defensive type checks — server is authoritative but we don't
		-- want a malformed payload (e.g., from a broken protocol after
		-- a partial deploy) to throw client-side and break the renderer
		-- for the rest of the session.
		if typeof(originPos) ~= "Vector3" or typeof(directionOrRadius) ~= "Vector3" or typeof(windupSec) ~= "number" then
			warn(`[BossTelegraph] malformed payload type — attackType={attackType}`)
			return
		end
		if windupSec <= 0 or windupSec > 5 then
			warn(`[BossTelegraph] suspicious windupSec={windupSec}; ignoring`)
			return
		end

		if attackType == "InfernoSlam" then
			-- For Slam, directionOrRadius.X carries the radius (Y/Z
			-- unused). Encoding as Vector3 keeps the remote signature
			-- uniform with Beam's direction.
			local radius = directionOrRadius.X
			if radius <= 0 or radius > 200 then return end -- sanity bound
			renderSlam(originPos, radius, windupSec)
		elseif attackType == "MagmaBeam" then
			renderBeam(originPos, directionOrRadius, windupSec)
		else
			warn(`[BossTelegraph] unknown attackType={attackType}`)
		end
	end)
end

return BossTelegraph
