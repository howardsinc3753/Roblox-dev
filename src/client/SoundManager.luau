--!strict
-- Sound effects manager.
-- Uses Roblox default/stock sound IDs for the proof-of-concept.

local SoundService = game:GetService("SoundService")

local SoundManager = {}

-- Roblox asset library sound IDs (free, no upload needed)
-- Using Roblox Pro Sound Effects partnership audio (permanently public, "(SFX)" assets)
-- and verified Creator Store audio. Old third-party IDs broke due to 2022 audio privacy update.
local SOUNDS: { [string]: { id: string, volume: number, pitch: number } } = {
	BreathFire = { id = "rbxassetid://9114444008", volume = 1.5, pitch = 1.2 }, -- Fire Whoosh 3 (SFX)
	Hit = { id = "rbxassetid://9113081793", volume = 1.2, pitch = 1.0 }, -- Airy Whoosh Blast 4 (SFX)
	KO = { id = "rbxassetid://9120705982", volume = 1.8, pitch = 0.8 }, -- Whoosh Explosion 1 (SFX)
	Special = { id = "rbxassetid://9066114566", volume = 1.5, pitch = 1.2 }, -- 8bit explosion (SFX)
	RoundStart = { id = "rbxassetid://9066114566", volume = 2.0, pitch = 1.5 }, -- 8bit explosion (SFX) high pitch as fanfare
	RoundEnd = { id = "rbxassetid://9066114566", volume = 1.5, pitch = 0.7 }, -- 8bit explosion (SFX) low pitch
	Coin = { id = "rbxassetid://9114444008", volume = 0.8, pitch = 2.5 }, -- Fire Whoosh pitched up as ding
	WingFlap = { id = "rbxassetid://9113081793", volume = 0.5, pitch = 0.4 }, -- Airy Whoosh low pitch as flap
	-- Sprint 7: deliberate-purchase chime. The existing "Coin" sound fires
	-- on every UpdateCoins event (kill rewards, wave bonuses, daily login,
	-- etc.) so it's noisy and doesn't read as a "you spent something" beat.
	-- Purchase is louder + lower-pitched than Coin to feel weightier — a
	-- "ka-ching" celebration the kid hears the moment they commit. Played
	-- by DragonUpgradeUI on successful upgrade and DragonSelectUI on
	-- dragon unlock click.
	Purchase = { id = "rbxassetid://9066114566", volume = 1.8, pitch = 1.3 }, -- 8bit explosion at celebratory pitch
}

local soundInstances: { [string]: Sound } = {}

function SoundManager.init()
	-- Pre-create sound instances for fast playback
	for name, config in SOUNDS do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = config.id
		sound.Volume = config.volume
		sound.PlaybackSpeed = config.pitch
		sound.Parent = SoundService
		soundInstances[name] = sound
	end
end

function SoundManager.play(name: string)
	local sound = soundInstances[name]
	if sound then
		-- Clone to allow overlapping plays
		local clone = sound:Clone()
		clone.Parent = SoundService
		clone:Play()
		clone.Ended:Connect(function()
			clone:Destroy()
		end)
	end
end

-- Element-specific layered SFX for special abilities. The previous
-- single-asset "8-bit explosion" sound was the same for every dragon
-- regardless of element — pretty unmemorable. By layering the verified
-- Pro-Sound-Effects assets at element-tuned pitch + volume, each
-- element's special reads distinctly without needing new asset uploads.
--
-- Each entry is a list of (assetId, volume, pitch) tuples — they all
-- play simultaneously as one "stack" sound. The combinations are tuned
-- by ear:
--   - low pitch + explosion = weight (Earth boom, Dark thud)
--   - high pitch + sparkle = energy (Light shimmer, Ice chime)
--   - layered whoosh + boom = power (Fire roar, Lightning crack)
local SPECIAL_SOUNDS_BY_ELEMENT: { [string]: { { id: string, volume: number, pitch: number } } } = {
	Fire = {
		{ id = "rbxassetid://9114444008", volume = 2.5, pitch = 0.7 }, -- deep fire whoosh
		{ id = "rbxassetid://9120705982", volume = 1.8, pitch = 0.85 }, -- explosion underbed
	},
	Ice = {
		{ id = "rbxassetid://9113081793", volume = 1.6, pitch = 1.5 }, -- crystalline whoosh
		{ id = "rbxassetid://9114444008", volume = 1.0, pitch = 2.4 }, -- shimmer chime overlay
	},
	Lightning = {
		{ id = "rbxassetid://9066114566", volume = 2.0, pitch = 2.0 }, -- electric zap (high pitch 8-bit)
		{ id = "rbxassetid://9120705982", volume = 1.6, pitch = 1.1 }, -- thunder crack
	},
	Earth = {
		{ id = "rbxassetid://9120705982", volume = 2.5, pitch = 0.4 }, -- deep rumble (very low explosion)
		{ id = "rbxassetid://9066114566", volume = 1.2, pitch = 0.55 }, -- heavy thud overlay
	},
	Dark = {
		{ id = "rbxassetid://9113081793", volume = 1.8, pitch = 0.55 }, -- sinister whoosh (low airy)
		{ id = "rbxassetid://9120705982", volume = 1.0, pitch = 0.45 }, -- ominous boom underbed
	},
	Light = {
		{ id = "rbxassetid://9114444008", volume = 1.2, pitch = 2.6 }, -- celestial shimmer
		{ id = "rbxassetid://9066114566", volume = 1.6, pitch = 1.8 }, -- bright tone overlay
	},
}

-- Plays the layered SFX stack for a given element's special. Used by
-- init.client.luau when specialEffectRemote fires. Falls back to the
-- generic Special sound if the element key is missing (defensive).
function SoundManager.playSpecialForElement(element: string)
	local stack = SPECIAL_SOUNDS_BY_ELEMENT[element]
	if not stack then
		SoundManager.play("Special")
		return
	end
	for _, config in stack do
		local sound = Instance.new("Sound")
		sound.SoundId = config.id
		sound.Volume = config.volume
		sound.PlaybackSpeed = config.pitch
		sound.Parent = SoundService
		sound:Play()
		sound.Ended:Connect(function() sound:Destroy() end)
	end
end

-- Background music: "Drinking Horns and Battle Cries" by DistrokidOfficial.
-- This is a Roblox marketplace asset (DistrokidOfficial is a Roblox music
-- partner — their tracks are licensed for use in any Roblox experience).
-- No upload needed; the asset is already approved and globally playable.
--
-- To swap: pick another Audio asset from create.roblox.com/store and replace
-- the ID below. Verify the creator is trusted (Distrokid, official Roblox
-- audio, or your own uploads) — random user uploads often get moderated away.
-- Two music tracks running in parallel: Lair (calm) + Arena (battle).
-- Both Sound objects play continuously at low volume; we crossfade their
-- volumes via SoundManager.setZone() based on the player's altitude. This
-- avoids start/stop pop and gives a smooth audio transition between zones.
local LAIR_MUSIC_ID = "rbxassetid://83298024686703" -- Rainy Window (user-Got'd)
local ARENA_MUSIC_ID = "rbxassetid://137677840690864" -- Drinking Horns (DistrokidOfficial)
local MUSIC_VOLUME = 0.25

local lairMusic: Sound? = nil
local arenaMusic: Sound? = nil

function SoundManager.startMusic()
	if lairMusic then return end -- already started

	lairMusic = Instance.new("Sound")
	lairMusic.Name = "LairMusic"
	lairMusic.SoundId = LAIR_MUSIC_ID
	lairMusic.Volume = MUSIC_VOLUME -- starts in Lair = full volume
	lairMusic.Looped = true
	lairMusic.Parent = SoundService
	lairMusic:Play()

	arenaMusic = Instance.new("Sound")
	arenaMusic.Name = "ArenaMusic"
	arenaMusic.SoundId = ARENA_MUSIC_ID
	arenaMusic.Volume = 0 -- silent in Lair, swells when player enters Arena
	arenaMusic.Looped = true
	arenaMusic.Parent = SoundService
	arenaMusic:Play()
end

-- Smoothly crossfade between Lair and Arena tracks based on whether the
-- player is currently in the Lair zone. Called from init.client.luau
-- Heartbeat with dt so the fade is frame-rate-independent.
function SoundManager.setZone(isInLair: boolean, dt: number)
	if not lairMusic or not arenaMusic then return end
	local lairTarget = if isInLair then MUSIC_VOLUME else 0
	local arenaTarget = if isInLair then 0 else MUSIC_VOLUME
	local alpha = 1 - math.exp(-1.5 * dt) -- ~1.3s for full crossfade
	lairMusic.Volume = lairMusic.Volume + (lairTarget - lairMusic.Volume) * alpha
	arenaMusic.Volume = arenaMusic.Volume + (arenaTarget - arenaMusic.Volume) * alpha
end

function SoundManager.stopMusic()
	if lairMusic then lairMusic:Destroy(); lairMusic = nil end
	if arenaMusic then arenaMusic:Destroy(); arenaMusic = nil end
end

function SoundManager.setMusicVolume(volume: number)
	-- Legacy single-volume setter; scales both tracks proportionally
	local v = math.clamp(volume, 0, 1)
	if lairMusic then lairMusic.Volume = v end
	if arenaMusic then arenaMusic.Volume = v end
end

function SoundManager.playAtPosition(name: string, position: Vector3)
	local config = SOUNDS[name]
	if not config then return end

	local part = Instance.new("Part")
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = game.Workspace

	local sound = Instance.new("Sound")
	sound.SoundId = config.id
	sound.Volume = config.volume
	sound.PlaybackSpeed = config.pitch
	sound.RollOffMaxDistance = 100
	sound.Parent = part
	sound:Play()

	sound.Ended:Connect(function()
		part:Destroy()
	end)
end

return SoundManager
