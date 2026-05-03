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

-- Background music: looped, plays continuously while client is alive.
-- Roblox audio library: 1837854434 is "Epic Battle" type loop. Tweak as desired.
local BACKGROUND_MUSIC_ID = "rbxassetid://1837854434"
local BACKGROUND_MUSIC_VOLUME = 0.25

local backgroundMusic: Sound? = nil

function SoundManager.startMusic()
	if backgroundMusic then return end
	backgroundMusic = Instance.new("Sound")
	backgroundMusic.Name = "BackgroundMusic"
	backgroundMusic.SoundId = BACKGROUND_MUSIC_ID
	backgroundMusic.Volume = BACKGROUND_MUSIC_VOLUME
	backgroundMusic.Looped = true
	backgroundMusic.Parent = SoundService
	backgroundMusic:Play()
end

function SoundManager.stopMusic()
	if backgroundMusic then
		backgroundMusic:Stop()
		backgroundMusic:Destroy()
		backgroundMusic = nil
	end
end

function SoundManager.setMusicVolume(volume: number)
	if backgroundMusic then
		backgroundMusic.Volume = math.clamp(volume, 0, 1)
	end
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
