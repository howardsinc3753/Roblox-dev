--!strict
-- Sound effects manager.
-- Uses Roblox default/stock sound IDs for the proof-of-concept.

local SoundService = game:GetService("SoundService")

local SoundManager = {}

-- Roblox asset library sound IDs (free, no upload needed)
local SOUNDS: { [string]: { id: string, volume: number, pitch: number } } = {
	BreathFire = { id = "rbxassetid://5765933027", volume = 0.6, pitch = 1.2 }, -- whoosh/fire
	Hit = { id = "rbxassetid://3932505857", volume = 0.5, pitch = 1.0 }, -- impact
	KO = { id = "rbxassetid://5765933272", volume = 0.7, pitch = 0.8 }, -- explosion
	Special = { id = "rbxassetid://5765933272", volume = 0.5, pitch = 1.5 }, -- power-up
	RoundStart = { id = "rbxassetid://5765933656", volume = 0.8, pitch = 1.0 }, -- fanfare
	RoundEnd = { id = "rbxassetid://5765933656", volume = 0.6, pitch = 0.7 }, -- lower fanfare
	Coin = { id = "rbxassetid://5765933027", volume = 0.3, pitch = 2.0 }, -- high-pitched ding
	WingFlap = { id = "rbxassetid://5765933027", volume = 0.15, pitch = 0.5 }, -- ambient flap
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
