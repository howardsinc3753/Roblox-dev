--!strict
-- Sprint 8: per-zone lighting tint. Shifts the global Lighting service
-- toward a purple-gold magical-realm feel when the player is in the
-- Lair, back to the combat-baseline tint when they're in the Arena.
--
-- Why client-side: Lighting is a shared service; tinting it server-side
-- would affect ALL players regardless of which zone they're in. The
-- only correct architecture is per-client based on the local player's
-- own Zone attribute (Sprint 5 ZoneManager). Each client renders its
-- own atmosphere.
--
-- Self-contained ScreenGui-free module — same isolation pattern as
-- SafeZoneIndicator and WaveTracker. A syntax error here can't take
-- HUD or any other gameplay system down. If this module fails, the
-- worst case is the Lighting service stays at its baseline values
-- (which is fine; the Lair is still playable, just less atmospheric).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local InsertService = game:GetService("InsertService")

local LairAtmosphere = {}

-- Sprint 10 Tier 3: dedicated boss-encounter Sky asset (night sky).
-- Loaded via InsertService at module init, cached for fast swap-in
-- when boss spawns. Cleaned up + restored on boss defeat/timeout —
-- the original Sky (whatever was in Lighting at module load) stays
-- untouched and gets re-parented when boss state flips back to false.
local BOSS_SKY_ASSET_ID = 90988519
local cachedBossSky: Sky? = nil
-- Reference to the Sky currently active in Lighting at module init.
-- Captured so we can restore it cleanly when the boss encounter ends.
local originalSky: Sky? = nil
-- Live reference to the boss-Sky CLONE currently parented to Lighting.
-- Distinct from cachedBossSky (the template) so we can destroy the
-- in-use clone on deactivate without losing the source instance.
local activeBossSky: Sky? = nil

local player = Players.LocalPlayer

-- Captured at init time so we can restore EXACTLY what the project's
-- baseline Lighting properties are (rather than hard-coding values
-- that might drift from the Studio Lighting settings). Saved on first
-- init() call; reused on every Arena entry.
local baseline: { Ambient: Color3, OutdoorAmbient: Color3, FogColor: Color3, FogEnd: number }? = nil

-- Lair atmosphere — purple-gold magical realm. Slightly tinted ambient
-- + warmer fog + closer fog distance so the volume feels enclosed and
-- "different world" from the Arena's open-sky setting. Subtle enough
-- not to wash out the dragon meshes.
local LAIR_AMBIENT = Color3.fromRGB(60, 40, 80)
local LAIR_OUTDOOR_AMBIENT = Color3.fromRGB(120, 90, 160)
local LAIR_FOG_COLOR = Color3.fromRGB(140, 90, 180)
local LAIR_FOG_END = 800 -- closer than typical outdoor

-- Sprint 10 Tier 2: boss-encounter atmosphere. Sky/ambient turns dark
-- red when Blaze appears in the Arena, restores on victory/timeout.
-- Layered ON TOP of the zone tint — the boss state takes priority over
-- Lair vs. Arena for the duration of the encounter. Reads as "the sky
-- itself reacts to the boss" without needing a custom skybox asset.
-- Once user uploads a custom dark skybox, swap the values here.
local BOSS_AMBIENT = Color3.fromRGB(80, 20, 20)
local BOSS_OUTDOOR_AMBIENT = Color3.fromRGB(100, 30, 30)
local BOSS_FOG_COLOR = Color3.fromRGB(120, 30, 20)
local BOSS_FOG_END = 600 -- pulled in further for "closing in" feel

local TWEEN_DURATION = 1.5 -- crossfade between zones, matches the music crossfade pace

-- Apply a target lighting set via TweenService. Generation guard prevents
-- a slow tween from a previous zone-change writing over a fresh tween if
-- the kid rapid-cycles the portal.
local generation = 0

local function applyLighting(target: { Ambient: Color3, OutdoorAmbient: Color3, FogColor: Color3, FogEnd: number })
	generation += 1
	local myGen = generation
	-- Tween Lighting properties directly. TweenService accepts the
	-- Lighting service as the target since it's a Roblox-derived
	-- Instance.
	local tween = TweenService:Create(Lighting,
		TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{
			Ambient = target.Ambient,
			OutdoorAmbient = target.OutdoorAmbient,
			FogColor = target.FogColor,
			FogEnd = target.FogEnd,
		}
	)
	tween:Play()
	-- No need to wait — tween runs to completion on its own thread.
	-- The myGen capture is here for future expansion (e.g., abort the
	-- tween if a newer one starts).
	_ = myGen
end

-- Sprint 10 Tier 2: boss-active flag. Set by setBossActive() when the
-- BossMusicState remote fires from the server. While active, refresh
-- chooses the boss tint regardless of zone — the boss takes priority
-- because Blaze spawns in the Arena and the kid is fighting him there.
local bossActive = false

local function refreshFromZone()
	if not baseline then return end
	-- Sprint 10 Tier 2: boss tint takes priority over zone tint.
	-- Cleared when bossActive flips back to false (victory/timeout).
	if bossActive then
		applyLighting({
			Ambient = BOSS_AMBIENT,
			OutdoorAmbient = BOSS_OUTDOOR_AMBIENT,
			FogColor = BOSS_FOG_COLOR,
			FogEnd = BOSS_FOG_END,
		})
		return
	end
	local zoneAttr = player:GetAttribute("Zone")
	-- Default to Lair if the attribute hasn't replicated yet — matches
	-- the first-spawn behavior + LairAtmosphere shows the magical
	-- realm tint on the kid's first frame.
	local inLair = zoneAttr == nil or zoneAttr == "Lair"
	if inLair then
		applyLighting({
			Ambient = LAIR_AMBIENT,
			OutdoorAmbient = LAIR_OUTDOOR_AMBIENT,
			FogColor = LAIR_FOG_COLOR,
			FogEnd = LAIR_FOG_END,
		})
	else
		applyLighting(baseline)
	end
end

-- Sprint 10 Tier 2/3: public toggle for boss state. Wired in
-- init.client.luau alongside the existing BossMusicState handler so
-- music + atmosphere + skybox swap together.
--
-- Three layered effects, each independent so a partial failure of one
-- doesn't break the others:
-- 1. Ambient + Fog tint (applyLighting via refreshFromZone)
-- 2. Custom dark skybox swap (this function — clones cachedBossSky
--    in, hides originalSky; reverses on deactivate)
-- 3. Music swap (handled in SoundManager.setBossMusicActive)
--
-- Sky swap is temporary by design — original Sky is preserved (just
-- re-parented out of Lighting on activate, back in on deactivate)
-- so the published place's normal sky resumes the moment the boss
-- encounter ends.
function LairAtmosphere.setBossActive(active: boolean)
	bossActive = active

	if active then
		-- Move original Sky out of Lighting (preserves it) + parent
		-- the boss Sky clone in. Refresh originalSky in case Lighting
		-- has been mutated by something else since init (defensive).
		if not originalSky then
			originalSky = Lighting:FindFirstChildOfClass("Sky")
		end
		if originalSky then
			-- Park it in nil so Lighting doesn't have two Sky children
			-- (Roblox uses the FIRST Sky child it finds; orphaning
			-- the original keeps it alive for restoration).
			originalSky.Parent = nil
		end
		if cachedBossSky and not activeBossSky then
			activeBossSky = cachedBossSky:Clone()
			activeBossSky.Parent = Lighting
		end
	else
		-- Tear down the boss Sky clone, restore original. Order
		-- matters: parent original BEFORE destroying clone so there's
		-- no flicker frame with no Sky in Lighting.
		if originalSky and not originalSky.Parent then
			originalSky.Parent = Lighting
		end
		if activeBossSky then
			activeBossSky:Destroy()
			activeBossSky = nil
		end
	end

	refreshFromZone()
end

function LairAtmosphere.init()
	-- Snapshot the baseline once. After this point, applyLighting can
	-- restore the project's exact Studio defaults regardless of how
	-- many tweens have run in between.
	baseline = {
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		FogColor = Lighting.FogColor,
		FogEnd = Lighting.FogEnd,
	}

	-- Sprint 10 Tier 3: capture whatever Sky is currently in Lighting
	-- so we can restore it after a boss encounter. The published place
	-- has its own Sky configured (defaults, custom, or Roblox's
	-- default skybox if neither). Storing the reference rather than
	-- cloning means we don't accidentally orphan the live Sky during
	-- the swap.
	originalSky = Lighting:FindFirstChildOfClass("Sky")

	-- Pre-load the boss Sky asset client-side via InsertService.
	-- Wrapped in pcall + task.spawn so a load failure (rare —
	-- marketplace assets are reliable) doesn't block init for the
	-- rest of the module. Falls through cleanly to the Ambient/Fog
	-- tint as the only boss-atmosphere effect.
	task.spawn(function()
		local ok, model = pcall(function()
			return InsertService:LoadAsset(BOSS_SKY_ASSET_ID)
		end)
		if not ok or not model then
			warn(`[LairAtmosphere] Failed to load boss Sky asset {BOSS_SKY_ASSET_ID}: {model}`)
			return
		end
		local sky = model:FindFirstChildOfClass("Sky")
		if sky then
			cachedBossSky = sky:Clone() -- detach from the loaded model
			model:Destroy() -- container no longer needed
		else
			warn(`[LairAtmosphere] Boss Sky asset loaded but no Sky child found`)
		end
	end)

	-- Apply initial state based on current Zone attribute (likely Lair
	-- since players spawn there). PlayerAdded → ZoneManager fires the
	-- first stamp by the time client init runs, so this should land
	-- correctly without race.
	refreshFromZone()

	player:GetAttributeChangedSignal("Zone"):Connect(refreshFromZone)
end

return LairAtmosphere
