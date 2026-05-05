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

-- Sprint 10 visual overhaul Tier 2: camera shake on attack impact.
-- Sibling client module — required for shake() calls in renderImpact.
local CameraShake = require(script.Parent.CameraShake)

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

-- ===== Magma Beam (Sprint 10 visual overhaul) =====
-- Original implementation was a static neon block that pulsed via tween.
-- Read as "red rectangle floating in air" rather than "fire beam." Now
-- uses Roblox's built-in Beam constraint between two attachments — the
-- engine handles texture animation natively, gets free transparency
-- gradients, and reads as an actual fire beam vs. a primitive shape.
--
-- Two phases:
-- 1. WINDUP: Beam at low width + low brightness, pulsing — telegraphs
--    "the beam is going to fire from HERE in this direction."
-- 2. FIRE: Beam at full width + max brightness for a brief flash, plus
--    a fire ParticleEmitter blasting out from the origin. After the
--    flash, fade to nothing.
local function renderBeam(originPos: Vector3, direction: Vector3, windupSec: number)
	local BEAM_LENGTH = 80
	if direction.Magnitude < 0.001 then return end
	local dirUnit = direction.Unit

	-- Two anchored points: one at the origin (the boss's "mouth"), one
	-- at the beam's terminus. Beam constraint draws the textured 2D
	-- effect between them.
	local originPart = Instance.new("Part")
	originPart.Name = "BlazeBeamOrigin"
	originPart.Size = Vector3.new(0.1, 0.1, 0.1)
	originPart.Transparency = 1
	originPart.Anchored = true
	originPart.CanCollide = false
	originPart.CFrame = CFrame.new(originPos)
	originPart.Parent = workspace

	local endPart = Instance.new("Part")
	endPart.Name = "BlazeBeamEnd"
	endPart.Size = Vector3.new(0.1, 0.1, 0.1)
	endPart.Transparency = 1
	endPart.Anchored = true
	endPart.CanCollide = false
	endPart.CFrame = CFrame.new(originPos + dirUnit * BEAM_LENGTH)
	endPart.Parent = workspace

	local originAttach = Instance.new("Attachment")
	originAttach.Parent = originPart
	local endAttach = Instance.new("Attachment")
	endAttach.Parent = endPart

	local beam = Instance.new("Beam")
	beam.Attachment0 = originAttach
	beam.Attachment1 = endAttach
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 80)),  -- bright at origin (boss mouth)
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 80, 30)), -- fiery middle
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 30, 20)),   -- darker at terminus
	})
	-- Width 0 (start) → wide (end) gives the beam a "flame cone" shape,
	-- but during windup we want it thin to read as "preview." Set both
	-- to the windup-thin width here; the FIRE phase tweens them up.
	beam.Width0 = 1.5
	beam.Width1 = 1.5
	beam.Transparency = NumberSequence.new(0.35) -- semi-transparent during windup
	beam.LightEmission = 0.8
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds" -- scrolling texture
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureSpeed = 2 -- scrolls toward the target, reads as energy flowing
	beam.FaceCamera = true
	beam.Parent = originPart

	-- Pulse the texture speed during windup so the beam visibly "charges."
	-- Goes from slow (boss is preparing) to fast (about to fire).
	local pulseTween = TweenService:Create(beam,
		TweenInfo.new(windupSec, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextureSpeed = 8 }
	)
	pulseTween:Play()

	Debris:AddItem(originPart, windupSec + 0.6)
	Debris:AddItem(endPart, windupSec + 0.6)

	task.delay(windupSec, function()
		if not beam.Parent then return end
		-- FIRE phase: ramp width up + transparency to opaque + spawn a
		-- fire particle stream from the origin point so the beam looks
		-- like an actual fire blast, not a static gradient.
		local fireWidth = TweenService:Create(beam,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Width0 = 4, Width1 = 6, Transparency = NumberSequence.new(0) }
		)
		fireWidth:Play()

		-- Fire particle emitter at origin, oriented along direction. The
		-- particles' Acceleration vector pushes them along the beam path
		-- so they look like flames riding the beam.
		local fireEmitter = Instance.new("ParticleEmitter")
		fireEmitter.Texture = "rbxasset://textures/particles/fire_main.dds"
		fireEmitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 80)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 40, 0)),
		})
		fireEmitter.Size = NumberSequence.new(3, 0.4)
		fireEmitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		fireEmitter.Lifetime = NumberRange.new(0.4, 0.8)
		fireEmitter.Rate = 200
		fireEmitter.Speed = NumberRange.new(40, 60)
		fireEmitter.SpreadAngle = Vector2.new(15, 15)
		-- Orient particles to fire along the beam direction. Roblox
		-- emits along the attachment's "up" axis by default; we orient
		-- the attachment so its up = our direction.
		originAttach.CFrame = CFrame.lookAt(Vector3.zero, dirUnit) * CFrame.Angles(math.rad(-90), 0, 0)
		fireEmitter.Parent = originAttach

		task.wait(0.4) -- let the burst stream visibly
		fireEmitter.Enabled = false

		-- Fade beam out
		local fadeOut = TweenService:Create(beam,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Transparency = NumberSequence.new(1) }
		)
		fadeOut:Play()
	end)
end

-- ===== On-impact explosion + charge-up (Sprint 10 visual overhaul) =====
-- Three flavors share this renderer: full-power explosion (Slam impact,
-- Beam terminus impact) and a smaller charge-up burst on the boss
-- before each attack telegraph. Same VFX building blocks (fire +
-- smoke + light) at different magnitudes, so layering reads as
-- coherent "fire-themed boss" instead of mismatched effects.
local function renderImpact(attackType: string, position: Vector3)
	-- Sprint 10 Tier 2: charge-up branch. Smaller burst — boss telegraphs
	-- "I'm winding up" via a brief fire flare on his body. No camera
	-- shake (would compete with the actual impact shake 1.8s later).
	if attackType == "ChargeUp" then
		local chargePart = Instance.new("Part")
		chargePart.Size = Vector3.new(0.1, 0.1, 0.1)
		chargePart.Transparency = 1
		chargePart.Anchored = true
		chargePart.CanCollide = false
		chargePart.CFrame = CFrame.new(position)
		chargePart.Parent = workspace
		Debris:AddItem(chargePart, 1.5)

		local chargeAttach = Instance.new("Attachment")
		chargeAttach.Parent = chargePart
		local chargeFire = Instance.new("ParticleEmitter")
		chargeFire.Texture = "rbxasset://textures/particles/fire_main.dds"
		chargeFire.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80))
		chargeFire.Size = NumberSequence.new(4, 0.5)
		chargeFire.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		chargeFire.Lifetime = NumberRange.new(0.4, 0.6)
		chargeFire.Rate = 0
		chargeFire.Speed = NumberRange.new(8, 14)
		chargeFire.SpreadAngle = Vector2.new(180, 180)
		chargeFire.Acceleration = Vector3.new(0, 8, 0)
		chargeFire.Parent = chargeAttach
		chargeFire:Emit(20) -- single burst

		local chargeLight = Instance.new("PointLight")
		chargeLight.Color = Color3.fromRGB(255, 200, 80)
		chargeLight.Brightness = 6
		chargeLight.Range = 25
		chargeLight.Parent = chargePart
		local chargeFade = TweenService:Create(chargeLight,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0 }
		)
		chargeFade:Play()
		return
	end
	-- Anchored center part to host the particle emitters + light.
	local impactPart = Instance.new("Part")
	impactPart.Name = "BlazeImpactVFX"
	impactPart.Size = Vector3.new(0.1, 0.1, 0.1)
	impactPart.Transparency = 1
	impactPart.Anchored = true
	impactPart.CanCollide = false
	impactPart.CFrame = CFrame.new(position)
	impactPart.Parent = workspace
	Debris:AddItem(impactPart, 2.5)

	-- Burst of fire particles
	local impactAttach = Instance.new("Attachment")
	impactAttach.Parent = impactPart
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 100)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 20, 10)),
	})
	fire.Size = NumberSequence.new(8, 0.5)
	fire.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	fire.Lifetime = NumberRange.new(0.6, 1.4)
	fire.Rate = 0 -- emitted in a single :Emit() burst
	fire.Speed = NumberRange.new(20, 50)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Acceleration = Vector3.new(0, 4, 0) -- slight rise
	fire.Parent = impactAttach
	fire:Emit(60) -- big burst

	-- Smoke ring expanding outward (separate emitter, layered behind fire)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(50, 30, 25))
	smoke.Size = NumberSequence.new(4, 12)
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(1.5, 2.5)
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(8, 18)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Parent = impactAttach
	smoke:Emit(30)

	-- PointLight flash — bright, fades fast. Sells the "boom" moment.
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 180, 80)
	light.Brightness = 12
	light.Range = if attackType == "InfernoSlam" then 50 else 35
	light.Parent = impactPart
	local lightTween = TweenService:Create(light,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }
	)
	lightTween:Play()

	-- Sprint 10 Tier 2: camera shake on impact. Slam is the bigger,
	-- heavier attack (radius hit) so it gets a more aggressive shake;
	-- Beam terminus impact is more focused, less full-body. Both decay
	-- over ~0.5s — long enough to feel, short enough not to nauseate.
	if attackType == "InfernoSlam" then
		CameraShake.shake(2.5, 0.5)
	else
		CameraShake.shake(1.5, 0.4)
	end
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

	-- Sprint 10 visual overhaul: on-impact VFX. Server fires this
	-- after the windup completes (separate moment from the telegraph
	-- start) so the client renders the explosion + light burst at
	-- the impact point.
	local impactRemote = remotes:WaitForChild("BossAttackImpact", 10) :: RemoteEvent?
	if impactRemote then
		impactRemote.OnClientEvent:Connect(function(attackType: string, position: Vector3)
			if typeof(position) ~= "Vector3" then return end
			renderImpact(attackType, position)
		end)
	end
end

return BossTelegraph
