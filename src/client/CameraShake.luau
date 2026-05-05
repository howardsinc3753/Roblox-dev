--!strict
-- Sprint 10 visual overhaul: camera shake on impactful moments.
--
-- Lightweight CFrame-perturbation shake that runs on RenderStepped
-- with priority Camera so it composes cleanly with whatever else is
-- driving the camera (CameraController's mouse-look, Roblox's
-- default follow cam, etc.). Shake is additive — we offset the
-- camera's CFrame by a noise-driven local-space transform per frame,
-- decaying to zero over the requested duration.
--
-- Public API: CameraShake.shake(intensity, duration). intensity in
-- studs (translation magnitude) + radians (rotation magnitude); a
-- value of 0.5 is "barely felt," 2 is "boss landed a slam," 5 is
-- "screen-rattling explosion." Duration in seconds. Multiple
-- concurrent shakes stack additively, so a slam during an
-- earthquake (none currently, but future-proofing) doesn't
-- override — they sum.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraShake = {}

-- Active shakes — list of records with progress / decay state.
type ShakeRecord = {
	intensity: number,
	duration: number,
	elapsed: number,
	seedX: number,
	seedY: number,
	seedZ: number,
}

local activeShakes: { ShakeRecord } = {}

-- Bind RenderStepped once at module load. The bound function reads
-- activeShakes each frame; when empty, it's a one-line no-op so the
-- per-frame cost during normal gameplay is negligible.
RunService:BindToRenderStep("BlazeCameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	if #activeShakes == 0 then return end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	-- Sum shake offsets across all active records. Each record
	-- contributes a noise-driven offset that decays to zero over its
	-- duration. Linear decay (1 - elapsed/duration) reads as a clean
	-- "burst then settle" feel.
	local totalOffsetX, totalOffsetY, totalOffsetZ = 0, 0, 0
	local totalRotX, totalRotY, totalRotZ = 0, 0, 0
	local now = tick()

	for i = #activeShakes, 1, -1 do
		local rec = activeShakes[i]
		rec.elapsed += dt
		if rec.elapsed >= rec.duration then
			table.remove(activeShakes, i)
			continue
		end
		-- Decay factor: 1.0 at start, 0.0 at end. Squared so the shake
		-- feels punchy on impact and tapers off smoothly.
		local decay = (1 - (rec.elapsed / rec.duration)) ^ 2
		-- Noise sampled with a tick()-based input so the perturbation
		-- jitters at ~60Hz independent of frame rate. math.noise gives
		-- smooth Perlin-style values in [-1, 1].
		local nx = math.noise(now * 25 + rec.seedX, 0, 0)
		local ny = math.noise(0, now * 25 + rec.seedY, 0)
		local nz = math.noise(0, 0, now * 25 + rec.seedZ)
		totalOffsetX += nx * rec.intensity * decay
		totalOffsetY += ny * rec.intensity * decay
		totalOffsetZ += nz * rec.intensity * decay
		-- Rotation perturbation — much smaller than translation so the
		-- shake doesn't make players motion-sick. ~5% of intensity in
		-- radians is the sweet spot.
		totalRotX += nx * rec.intensity * 0.005 * decay
		totalRotY += ny * rec.intensity * 0.005 * decay
		totalRotZ += nz * rec.intensity * 0.005 * decay
	end

	-- Apply the shake as a local-space CFrame offset on the camera. Use
	-- camera.CFrame * offset (post-multiply) so the perturbation moves
	-- with whatever direction the camera is facing — feels natural
	-- regardless of where the player is looking.
	camera.CFrame = camera.CFrame * CFrame.new(totalOffsetX, totalOffsetY, totalOffsetZ)
		* CFrame.Angles(totalRotX, totalRotY, totalRotZ)
end)

-- Public: trigger a shake. Returns nothing — fire-and-forget.
function CameraShake.shake(intensity: number, duration: number)
	if intensity <= 0 or duration <= 0 then return end
	-- Cap intensity at 8 studs to prevent a runaway "screen flying off
	-- camera" if a caller passes something silly. 8 is already
	-- "earthquake" territory.
	intensity = math.clamp(intensity, 0, 8)
	duration = math.clamp(duration, 0.05, 3)
	table.insert(activeShakes, {
		intensity = intensity,
		duration = duration,
		elapsed = 0,
		-- Random seeds so multiple shakes don't sample the same noise
		-- input and visually align (which would defeat the additive
		-- summation purpose).
		seedX = math.random() * 1000,
		seedY = math.random() * 1000,
		seedZ = math.random() * 1000,
	})
end

return CameraShake
