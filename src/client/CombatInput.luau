--!strict
-- Handles combat input: left-click breath attack, E/right-click special ability.
-- Sends events to server and creates visual effects locally.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SoundService = game:GetService("SoundService")
local DragonConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("DragonConfig"))

local CombatInput = {}

-- Quick local sound play for immediate feedback
local function playQuickSound(soundId: string, volume: number, pitch: number)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function() sound:Destroy() end)
end

local player = Players.LocalPlayer
local camera = game.Workspace.CurrentCamera
local enabled = false
local currentDragonId = "Ember"

-- Cooldown tracking (client-side prediction)
local lastBreathTime = 0
local lastSpecialTime = 0
local BREATH_COOLDOWN = 0.5
local SPECIAL_COOLDOWN = 10.0

-- Remotes (set after they're available)
local fireBreathRemote: RemoteEvent?
local useSpecialRemote: RemoteEvent?

function CombatInput.init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	fireBreathRemote = remotes:WaitForChild("FireBreath") :: RemoteEvent
	useSpecialRemote = remotes:WaitForChild("UseSpecial") :: RemoteEvent
end

function CombatInput.setDragon(dragonId: string)
	currentDragonId = dragonId
end

function CombatInput.enable()
	enabled = true
end

function CombatInput.disable()
	enabled = false
end

function CombatInput.getBreathCooldownPercent(): number
	local elapsed = tick() - lastBreathTime
	return math.clamp(elapsed / BREATH_COOLDOWN, 0, 1)
end

function CombatInput.getSpecialCooldownPercent(): number
	local elapsed = tick() - lastSpecialTime
	return math.clamp(elapsed / SPECIAL_COOLDOWN, 0, 1)
end

-- Create a visual breath projectile
local function createBreathEffect(origin: Vector3, direction: Vector3, color: Color3)
	local projectile = Instance.new("Part")
	projectile.Name = "BreathProjectile"
	projectile.Size = Vector3.new(2, 2, 4)
	projectile.Shape = Enum.PartType.Ball
	projectile.Color = color
	projectile.Material = Enum.Material.Neon
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CFrame = CFrame.new(origin, origin + direction)
	projectile.Parent = game.Workspace

	-- Particle trail
	local attachment = Instance.new("Attachment")
	attachment.Parent = projectile

	local trail = Instance.new("Trail")
	trail.Color = ColorSequence.new(color)
	trail.Lifetime = 0.3
	trail.MinLength = 0.1
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })

	local attachment2 = Instance.new("Attachment")
	attachment2.Position = Vector3.new(0, 0, 1)
	attachment2.Parent = projectile
	trail.Attachment0 = attachment
	trail.Attachment1 = attachment2
	trail.Parent = projectile

	-- Fly forward and destroy
	local speed = 150
	local distance = 100
	local duration = distance / speed

	local endPos = origin + direction.Unit * distance
	local tween = TweenService:Create(projectile, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		CFrame = CFrame.new(endPos, endPos + direction),
	})
	tween:Play()
	tween.Completed:Connect(function()
		projectile:Destroy()
	end)
end

-- Input handlers
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or not enabled then return end

	-- Left click: Breath attack
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if (tick() - lastBreathTime) < BREATH_COOLDOWN then return end

		local character = player.Character
		if not character or not character.PrimaryPart then return end

		local origin = character.PrimaryPart.Position + camera.CFrame.LookVector * 5
		local direction = camera.CFrame.LookVector

		lastBreathTime = tick()

		-- Send to server
		if fireBreathRemote then
			fireBreathRemote:FireServer(origin, direction)
		end

		-- Visual effect + sound
		local dragon = DragonConfig[currentDragonId]
		if dragon then
			createBreathEffect(origin, direction, dragon.color)
			playQuickSound("rbxassetid://9114444008", 1.5, 1.2) -- Fire Whoosh 3 (SFX)
		end
	end

	-- E key or Right click: Special ability
	if input.KeyCode == Enum.KeyCode.E or input.UserInputType == Enum.UserInputType.MouseButton2 then
		if (tick() - lastSpecialTime) < SPECIAL_COOLDOWN then return end

		lastSpecialTime = tick()

		if useSpecialRemote then
			useSpecialRemote:FireServer()
		end

		-- TODO: special ability visual effects per element
	end
end)

return CombatInput
