--!strict
-- Handles combat input: left-click breath attack, E/right-click special ability.
-- Sends events to server and creates visual effects locally.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SoundService = game:GetService("SoundService")
local DragonConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("DragonConfig"))
local LockOnController = require(script.Parent.LockOnController)
local DragonSelectUI = require(script.Parent.DragonSelectUI)

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

-- Element-specific breath visuals. Each entry tunes the projectile shape,
-- color, light, and particle texture so a fireball reads as fire, an ice
-- shard reads as ice, etc. — instead of a generic colored ball.
type ElementVFX = {
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	rotation: CFrame?, -- additional rotation applied to projectile (e.g., to make blocks look diamond)
	lightColor: Color3,
	lightBrightness: number,
	lightRange: number,
	particleTexture: string,
	particleColor: ColorSequence,
	particleRate: number,
	particleSpeed: NumberRange,
	particleSize: NumberSequence,
	trailColor: ColorSequence?,
	trailLightEmission: number,
}

local ELEMENT_VFX: { [string]: ElementVFX } = {
	Fire = {
		shape = Enum.PartType.Ball,
		size = Vector3.new(2.5, 2.5, 2.5),
		color = Color3.fromRGB(255, 120, 30),
		material = Enum.Material.Neon,
		lightColor = Color3.fromRGB(255, 150, 50),
		lightBrightness = 3,
		lightRange = 18,
		particleTexture = "rbxasset://textures/particles/fire_main.dds",
		particleColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 80)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 0)),
		}),
		particleRate = 100,
		particleSpeed = NumberRange.new(8, 14),
		particleSize = NumberSequence.new(2, 0.2),
		trailLightEmission = 1,
	},
	Ice = {
		shape = Enum.PartType.Block,
		size = Vector3.new(1.8, 1.8, 3),
		color = Color3.fromRGB(180, 230, 255),
		material = Enum.Material.Glass,
		rotation = CFrame.Angles(0, 0, math.rad(45)), -- diamond orientation
		lightColor = Color3.fromRGB(150, 220, 255),
		lightBrightness = 2,
		lightRange = 14,
		particleTexture = "rbxasset://textures/particles/sparkles_main.dds",
		particleColor = ColorSequence.new(Color3.fromRGB(220, 240, 255)),
		particleRate = 60,
		particleSpeed = NumberRange.new(4, 8),
		particleSize = NumberSequence.new(0.8, 0.1),
		trailLightEmission = 0.6,
	},
	Lightning = {
		shape = Enum.PartType.Ball,
		size = Vector3.new(2, 2, 2),
		color = Color3.fromRGB(255, 255, 100),
		material = Enum.Material.Neon,
		lightColor = Color3.fromRGB(220, 220, 255),
		lightBrightness = 4,
		lightRange = 20,
		particleTexture = "rbxasset://textures/particles/sparkles_main.dds",
		particleColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 180)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 80, 255)),
		}),
		particleRate = 150,
		particleSpeed = NumberRange.new(10, 20),
		particleSize = NumberSequence.new(1.2, 0.1),
		trailLightEmission = 1,
	},
	Earth = {
		shape = Enum.PartType.Block,
		size = Vector3.new(2.5, 2.5, 2.5),
		color = Color3.fromRGB(120, 80, 40),
		material = Enum.Material.Slate,
		rotation = CFrame.Angles(math.rad(20), math.rad(20), math.rad(20)),
		lightColor = Color3.fromRGB(140, 100, 60),
		lightBrightness = 1,
		lightRange = 8,
		particleTexture = "rbxasset://textures/particles/smoke_main.dds",
		particleColor = ColorSequence.new(Color3.fromRGB(100, 70, 40)),
		particleRate = 80,
		particleSpeed = NumberRange.new(3, 6),
		particleSize = NumberSequence.new(2, 0.5),
		trailLightEmission = 0,
	},
	Dark = {
		shape = Enum.PartType.Ball,
		size = Vector3.new(2.5, 2.5, 2.5),
		color = Color3.fromRGB(50, 20, 70),
		material = Enum.Material.Neon,
		lightColor = Color3.fromRGB(100, 30, 150),
		lightBrightness = 2,
		lightRange = 12,
		particleTexture = "rbxasset://textures/particles/smoke_main.dds",
		particleColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 30, 120)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 5, 30)),
		}),
		particleRate = 120,
		particleSpeed = NumberRange.new(5, 10),
		particleSize = NumberSequence.new(2.5, 0.5),
		trailLightEmission = 0.3,
	},
	Light = {
		shape = Enum.PartType.Ball,
		size = Vector3.new(2.2, 2.2, 2.2),
		color = Color3.fromRGB(255, 250, 220),
		material = Enum.Material.Neon,
		lightColor = Color3.fromRGB(255, 250, 200),
		lightBrightness = 5,
		lightRange = 22,
		particleTexture = "rbxasset://textures/particles/sparkles_main.dds",
		particleColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 150)),
		}),
		particleRate = 120,
		particleSpeed = NumberRange.new(6, 12),
		particleSize = NumberSequence.new(1.5, 0.2),
		trailLightEmission = 1,
	},
}

-- Create a visual breath projectile keyed off the dragon's element so each
-- type reads distinctly: Ember = fireball, Frost = ice shard, Storm = electric
-- ball, etc. Falls back to Fire styling if the element isn't in the table.
local function createBreathEffect(origin: Vector3, direction: Vector3, element: string, color: Color3)
	local vfx = ELEMENT_VFX[element] or ELEMENT_VFX.Fire

	local projectile = Instance.new("Part")
	projectile.Name = "BreathProjectile"
	projectile.Size = vfx.size
	projectile.Shape = vfx.shape
	projectile.Color = vfx.color
	projectile.Material = vfx.material
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.Massless = true
	-- Rotate to face direction. If the element wants extra orientation
	-- (e.g., diamond-spinning ice shard), apply that on top.
	local baseCF = CFrame.lookAt(origin, origin + direction)
	if vfx.rotation then
		projectile.CFrame = baseCF * vfx.rotation
	else
		projectile.CFrame = baseCF
	end
	projectile.Parent = workspace

	-- Glow light so the projectile illuminates terrain as it passes
	local light = Instance.new("PointLight")
	light.Color = vfx.lightColor
	light.Brightness = vfx.lightBrightness
	light.Range = vfx.lightRange
	light.Parent = projectile

	-- Particle emitter for element-specific texture (fire, sparkles, smoke...)
	local pAttach = Instance.new("Attachment")
	pAttach.Parent = projectile
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = vfx.particleTexture
	particles.Color = vfx.particleColor
	particles.Size = vfx.particleSize
	particles.Transparency = NumberSequence.new(0.1, 1)
	particles.Lifetime = NumberRange.new(0.3, 0.6)
	particles.Rate = vfx.particleRate
	particles.Speed = vfx.particleSpeed
	particles.SpreadAngle = Vector2.new(15, 15)
	particles.Parent = pAttach

	-- Streaming trail behind the projectile (kept from old impl, just colored)
	local trailAttach1 = Instance.new("Attachment")
	trailAttach1.Position = Vector3.new(0, 0, -0.5)
	trailAttach1.Parent = projectile
	local trailAttach2 = Instance.new("Attachment")
	trailAttach2.Position = Vector3.new(0, 0, 0.5)
	trailAttach2.Parent = projectile
	local trail = Instance.new("Trail")
	trail.Color = vfx.trailColor or ColorSequence.new(vfx.color)
	trail.Lifetime = 0.3
	trail.MinLength = 0.1
	trail.LightEmission = vfx.trailLightEmission
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.Attachment0 = trailAttach1
	trail.Attachment1 = trailAttach2
	trail.Parent = projectile

	-- Fly forward and destroy
	local speed = 150
	local distance = 100
	local duration = distance / speed
	local endPos = origin + direction.Unit * distance
	local tween = TweenService:Create(projectile, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(endPos, endPos + direction) * (vfx.rotation or CFrame.new()),
	})
	tween:Play()
	tween.Completed:Connect(function()
		particles.Enabled = false
		task.wait(0.3) -- let trailing particles fade naturally
		projectile:Destroy()
	end)
end

-- ============================================================================
-- INPUT HANDLERS — keyboard/mouse OR PS5/Xbox gamepad
-- ============================================================================
-- Refactored from inline branches to two action handlers (fireBreath /
-- fireSpecial) so the same code path serves both LMB and RT, and both
-- E-key and LT. Adding more input sources later only needs a new bind
-- in InputBegan, not a code-duplicated branch.

local function fireBreath()
	if not enabled then return end
	if (tick() - lastBreathTime) < BREATH_COOLDOWN then return end

	local character = player.Character
	if not character or not character.PrimaryPart then return end

	local origin = character.PrimaryPart.Position + camera.CFrame.LookVector * 5
	local direction = camera.CFrame.LookVector

	-- Aim assist: if a target is locked AND within ~30deg of camera,
	-- snap firing direction to point exactly at target. Casual aim help
	-- without bypassing skill — you still have to roughly aim. Server
	-- still validates the resulting direction with its own cone test,
	-- so this is safe (can't be exploited to fire backward).
	-- This is doubly important on console: thumbstick aim is less precise
	-- than a mouse, so the snap is more frequently the difference between
	-- "hit" and "miss" for kids.
	local lockedTarget = LockOnController.getLockedTarget()
	if lockedTarget and lockedTarget.rootPart and lockedTarget.rootPart.Parent then
		local toTarget = lockedTarget.rootPart.Position - origin
		if toTarget.Magnitude > 0.001 then
			local targetDir = toTarget.Unit
			if direction:Dot(targetDir) > 0.866 then
				direction = targetDir
			end
		end
	end

	lastBreathTime = tick()

	if fireBreathRemote then
		fireBreathRemote:FireServer(origin, direction)
	end

	local dragon = DragonConfig[currentDragonId]
	if dragon then
		createBreathEffect(origin, direction, dragon.element, dragon.color)
		playQuickSound("rbxassetid://9114444008", 1.5, 1.2) -- Fire Whoosh 3 (SFX)
	end
end

local function fireSpecial()
	if not enabled then return end
	if (tick() - lastSpecialTime) < SPECIAL_COOLDOWN then return end

	lastSpecialTime = tick()

	if useSpecialRemote then
		useSpecialRemote:FireServer(camera.CFrame.LookVector)
	end
end

-- Public proxies so MobileControls (touch buttons) can trigger the same
-- actions as the keyboard/mouse without us synthesizing fake input events.
function CombatInput.fireBreath()
	fireBreath()
end

function CombatInput.fireSpecial()
	fireSpecial()
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	-- Hard gate: combat inputs are dropped while the dragon-select menu is
	-- open. The kid clicking through the menu shouldn't accidentally fire
	-- breath at whoever's behind the modal. fireBreath/fireSpecial themselves
	-- already check `enabled`, but `enabled` is on for the round even with
	-- the menu open — we need a second guard for the menu specifically.
	if DragonSelectUI.isOpen() then return end

	-- Breath attack: LMB (mouse) OR RT (R2 on PS5, Right Trigger on Xbox)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2 then
		fireBreath()
	end

	-- Special ability: E (keyboard), Right Click, OR LT (L2 / Left Trigger)
	if input.KeyCode == Enum.KeyCode.E
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.KeyCode == Enum.KeyCode.ButtonL2 then
		fireSpecial()
	end
end)

return CombatInput
