--!strict
-- Dragon Warz — Client Entry Point
-- Wires up flight, camera, combat, HUD, sounds, and special effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

-- Wait for remotes to be created by server
local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not remotes then
	warn("[Client] Timed out waiting for Remotes folder")
	return
end

-- Load client modules
local FlightController = require(script.FlightController)
local CameraController = require(script.CameraController)
local CombatInput = require(script.CombatInput)
local HUD = require(script.HUD)
local SoundManager = require(script.SoundManager)
local DragonSelectUI = require(script.DragonSelectUI)
local RoundEndSummary = require(script.RoundEndSummary)

print(`[Client] {player.Name} Dragon Warz client starting...`)

-- Initialize systems
CombatInput.init()
HUD.create()
SoundManager.init()
SoundManager.startMusic()
DragonSelectUI.init()
DragonSelectUI.create()
RoundEndSummary.create()

-- Fetch initial player data so DragonSelectUI knows what's unlocked + selected.
-- The server creates the GetPlayerData RemoteFunction in NetworkSetup; it returns
-- the cached PlayerData table. Wrapped in pcall + retry because remotes may not
-- be ready at first script execution depending on join timing.
task.spawn(function()
	local getPlayerDataFunc = remotes:WaitForChild("GetPlayerData", 10) :: RemoteFunction?
	if not getPlayerDataFunc then return end
	-- Wait briefly so server's PlayerAdded handler has finished loadPlayer
	task.wait(1)
	local ok, data = pcall(function()
		return getPlayerDataFunc:InvokeServer()
	end)
	if ok and data then
		DragonSelectUI.updatePlayerData(data)
	end
end)

-- Current state
local currentDragonId = "Ember"
local INTERMISSION_DURATION = 15

-- ================================
-- REMOTE EVENT HANDLERS
-- ================================

local spawnDragonRemote = remotes:WaitForChild("SpawnDragon") :: RemoteEvent
local updateCoinsRemote = remotes:WaitForChild("UpdateCoins") :: RemoteEvent
local damagePlayerRemote = remotes:WaitForChild("DamagePlayer") :: RemoteEvent
local playerKORemote = remotes:WaitForChild("PlayerKO") :: RemoteEvent
local roundStartRemote = remotes:WaitForChild("RoundStart") :: RemoteEvent
local roundEndRemote = remotes:WaitForChild("RoundEnd") :: RemoteEvent
local updateScoreboardRemote = remotes:WaitForChild("UpdateScoreboard") :: RemoteEvent
local syncTimerRemote = remotes:WaitForChild("SyncTimer") :: RemoteEvent
local specialEffectRemote = remotes:WaitForChild("SpecialEffect") :: RemoteEvent
local damageNPCRemote = remotes:WaitForChild("DamageNPC") :: RemoteEvent
local npcBreathFiredRemote = remotes:WaitForChild("NPCBreathFired") :: RemoteEvent

-- Dragon spawned/changed
spawnDragonRemote.OnClientEvent:Connect(function(dragonId: string)
	currentDragonId = dragonId
	FlightController.setDragon(dragonId)
	CombatInput.setDragon(dragonId)
	HUD.setDragon(dragonId)

	task.defer(function()
		local character = player.Character or player.CharacterAdded:Wait()
		character:WaitForChild("HumanoidRootPart", 5)
		FlightController.enable()
		CameraController.enable()
		CombatInput.enable()
	end)
end)

-- Coins updated
updateCoinsRemote.OnClientEvent:Connect(function(coins: number)
	HUD.updateCoins(coins)
	DragonSelectUI.updateCoins(coins)
	SoundManager.play("Coin")
end)

-- Reusable floating damage number — used for both player hits and NPC hits.
-- Adornee accepts any BasePart so we can show numbers above NPC root parts too.
local function showFloatingDamage(adornee: BasePart, damage: number)
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Size = UDim2.fromOffset(100, 40)
	billboardGui.StudsOffset = Vector3.new(math.random(-2, 2), 6, 0)
	billboardGui.Adornee = adornee
	billboardGui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = `-{damage}`
	label.TextColor3 = Color3.fromRGB(255, 50, 50)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboardGui

	task.spawn(function()
		for i = 1, 20 do
			task.wait(0.05)
			billboardGui.StudsOffset += Vector3.new(0, 0.2, 0)
			label.TextTransparency = i / 20
			label.TextStrokeTransparency = i / 20
		end
		billboardGui:Destroy()
	end)
end

-- Damage dealt to a player (PvP)
damagePlayerRemote.OnClientEvent:Connect(function(targetUserId: number, damage: number)
	SoundManager.play("Hit")

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if targetPlayer and targetPlayer.Character then
		local rootPart = targetPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			showFloatingDamage(rootPart, damage)
		end
	end
end)

-- H1+H3 fix: damage dealt to an NPC. Server fires this to the SHOOTER ONLY
-- (so others' combat doesn't spam our hit sound). We render a floating "-X"
-- above the NPC's root part.
damageNPCRemote.OnClientEvent:Connect(function(npcModel: Model, damage: number)
	if not npcModel or not npcModel.PrimaryPart then return end
	SoundManager.play("Hit")
	showFloatingDamage(npcModel.PrimaryPart, damage)
end)

-- H2 fix: render a visible projectile from an attacking NPC to its target.
-- Fired to all clients so everyone sees the breath, not just the victim.
npcBreathFiredRemote.OnClientEvent:Connect(function(npcModel: Model, targetPos: Vector3, color: Color3)
	if not npcModel or not npcModel.PrimaryPart then return end
	local origin = npcModel.PrimaryPart.Position
	local direction = (targetPos - origin)
	if direction.Magnitude < 0.1 then return end
	direction = direction.Unit

	-- Projectile: same general look as player breath but tinted to the NPC color
	local projectile = Instance.new("Part")
	projectile.Name = "NPCBreath"
	projectile.Size = Vector3.new(2, 2, 4)
	projectile.Shape = Enum.PartType.Ball
	projectile.Color = color
	projectile.Material = Enum.Material.Neon
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CFrame = CFrame.lookAt(origin, origin + direction)
	projectile.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = projectile
	local attachment2 = Instance.new("Attachment")
	attachment2.Position = Vector3.new(0, 0, 1)
	attachment2.Parent = projectile
	local trail = Instance.new("Trail")
	trail.Color = ColorSequence.new(color)
	trail.Lifetime = 0.3
	trail.MinLength = 0.1
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.Attachment0 = attachment
	trail.Attachment1 = attachment2
	trail.Parent = projectile

	local distance = (targetPos - origin).Magnitude
	local speed = 150
	local duration = math.min(distance / speed, 1.0) -- cap so very long shots don't linger
	local endPos = origin + direction * distance

	local TweenService = game:GetService("TweenService")
	local tween = TweenService:Create(projectile, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(endPos, endPos + direction),
	})
	tween:Play()
	tween.Completed:Connect(function()
		projectile:Destroy()
	end)
end)

-- Player KO. Server fires this for player-vs-player AND for NPC kills:
--   killerUserId=0  → killed by NPC (enemyName carries the enemy type)
--   victimUserId=0  → player killed an NPC (enemyName carries the enemy type)
playerKORemote.OnClientEvent:Connect(function(killerUserId: number, victimUserId: number, enemyName: string?)
	local killerName: string
	local victimName: string

	if killerUserId == 0 then
		-- NPC killed a player
		killerName = enemyName or "Enemy"
	else
		local killer = Players:GetPlayerByUserId(killerUserId)
		killerName = if killer then killer.Name else "???"
	end

	if victimUserId == 0 then
		-- Player killed an NPC
		victimName = enemyName or "Enemy"
	else
		local victim = Players:GetPlayerByUserId(victimUserId)
		victimName = if victim then victim.Name else "???"
	end

	HUD.addKillFeed(killerName, victimName)
	SoundManager.play("KO")

	if victimUserId == player.UserId then
		HUD.updateRoundTimer("Eliminated! Respawning in 5s...")
		FlightController.disable()
		CombatInput.disable()

		task.delay(5, function()
			FlightController.enable()
			CombatInput.enable()
		end)
	end
end)

-- Round start: hide dragon select, return mouse to lock-center for combat
local roundTimeRemaining = 0
roundStartRemote.OnClientEvent:Connect(function(roundNumber: number, duration: number)
	roundTimeRemaining = duration
	HUD.updateRoundTimer(`Round {roundNumber} - {duration}s`)
	SoundManager.play("RoundStart")
	DragonSelectUI.hide()
	FlightController.enable()
	CameraController.enable()
	CombatInput.enable()
end)

-- Round end: show summary first, then dragon select for the rest of intermission.
-- Server now sends a third arg (coinsEarned per userId) for the personal payout.
roundEndRemote.OnClientEvent:Connect(function(winnerUserId: number, scoreboard: any, coinsEarned: any)
	local winner = Players:GetPlayerByUserId(winnerUserId)
	local winnerName = if winner then winner.Name else "No one"
	HUD.updateRoundTimer(`Round Over! Winner: {winnerName}`)
	SoundManager.play("RoundEnd")

	FlightController.disable()
	CombatInput.disable()

	-- Show summary first (auto-dismisses after ~6s), then open dragon select
	-- for the remaining intermission time.
	RoundEndSummary.show(winnerUserId, scoreboard, coinsEarned)
	task.delay(6, function()
		DragonSelectUI.show(9) -- ~9s left of the 15s intermission after summary
	end)
end)

-- Timer sync from server
syncTimerRemote.OnClientEvent:Connect(function(timeRemaining: number, roundNumber: number)
	roundTimeRemaining = timeRemaining
end)

-- Special ability visual effects
specialEffectRemote.OnClientEvent:Connect(function(userId: number, element: string, position: Vector3)
	SoundManager.play("Special")
	local targetPlayer = Players:GetPlayerByUserId(userId)
	if not targetPlayer or not targetPlayer.Character then return end
	local rootPart = targetPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	if element == "Fire" then
		-- Fire burst: expanding red sphere
		local burst = Instance.new("Part")
		burst.Shape = Enum.PartType.Ball
		burst.Size = Vector3.new(4, 4, 4)
		burst.Position = position
		burst.Color = Color3.fromRGB(255, 80, 20)
		burst.Material = Enum.Material.Neon
		burst.Anchored = true
		burst.CanCollide = false
		burst.Transparency = 0.3
		burst.Parent = game.Workspace

		task.spawn(function()
			for i = 1, 15 do
				task.wait(0.03)
				burst.Size = Vector3.new(4 + i * 5, 4 + i * 5, 4 + i * 5)
				burst.Transparency = 0.3 + (i / 15) * 0.7
			end
			burst:Destroy()
		end)

	elseif element == "Ice" then
		-- Ice wall: blue shield sphere
		local shield = Instance.new("Part")
		shield.Shape = Enum.PartType.Ball
		shield.Size = Vector3.new(15, 15, 15)
		shield.Position = position
		shield.Color = Color3.fromRGB(100, 180, 255)
		shield.Material = Enum.Material.ForceField
		shield.Anchored = true
		shield.CanCollide = false
		shield.Transparency = 0.5
		shield.Parent = game.Workspace

		task.delay(2, function() shield:Destroy() end)

	elseif element == "Lightning" then
		-- Lightning flash: yellow flash on nearby parts
		local flash = Instance.new("Part")
		flash.Shape = Enum.PartType.Ball
		flash.Size = Vector3.new(60, 60, 60)
		flash.Position = position
		flash.Color = Color3.fromRGB(255, 255, 50)
		flash.Material = Enum.Material.Neon
		flash.Anchored = true
		flash.CanCollide = false
		flash.Transparency = 0.7
		flash.Parent = game.Workspace

		task.spawn(function()
			for i = 1, 5 do
				task.wait(0.05)
				flash.Transparency = if i % 2 == 0 then 0.7 else 0.4
			end
			flash:Destroy()
		end)

	elseif element == "Earth" then
		-- Rock armor: brown glow
		local glow = Instance.new("Part")
		glow.Shape = Enum.PartType.Ball
		glow.Size = Vector3.new(12, 12, 12)
		glow.Position = position
		glow.Color = Color3.fromRGB(139, 119, 80)
		glow.Material = Enum.Material.Neon
		glow.Anchored = true
		glow.CanCollide = false
		glow.Transparency = 0.4
		glow.Parent = game.Workspace

		task.spawn(function()
			for i = 1, 10 do
				task.wait(0.05)
				glow.Transparency = 0.4 + (i / 10) * 0.6
			end
			glow:Destroy()
		end)

	elseif element == "Dark" then
		-- Shadow: dark mist puff
		local mist = Instance.new("Part")
		mist.Shape = Enum.PartType.Ball
		mist.Size = Vector3.new(20, 20, 20)
		mist.Position = position
		mist.Color = Color3.fromRGB(30, 10, 40)
		mist.Material = Enum.Material.Neon
		mist.Anchored = true
		mist.CanCollide = false
		mist.Transparency = 0.3
		mist.Parent = game.Workspace

		task.spawn(function()
			for i = 1, 20 do
				task.wait(0.05)
				mist.Transparency = 0.3 + (i / 20) * 0.7
				mist.Size = Vector3.new(20 + i, 20 + i, 20 + i)
			end
			mist:Destroy()
		end)

	elseif element == "Light" then
		-- Heal pulse: white expanding ring
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(1, 10, 10)
		ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
		ring.Color = Color3.fromRGB(255, 255, 255)
		ring.Material = Enum.Material.Neon
		ring.Anchored = true
		ring.CanCollide = false
		ring.Transparency = 0.3
		ring.Parent = game.Workspace

		task.spawn(function()
			for i = 1, 15 do
				task.wait(0.04)
				local s = 10 + i * 6
				ring.Size = Vector3.new(1, s, s)
				ring.Transparency = 0.3 + (i / 15) * 0.7
			end
			ring:Destroy()
		end)
	end
end)

-- ================================
-- HUD UPDATE LOOP
-- ================================

RunService.Heartbeat:Connect(function(dt: number)
	-- Update health from humanoid (now synced by server)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			HUD.updateHealth(humanoid.Health, humanoid.MaxHealth)
		end
	end

	-- Update boost meter
	HUD.updateBoost(FlightController.getBoostPercent())

	-- Update cooldown indicators
	HUD.updateCooldowns(
		CombatInput.getBreathCooldownPercent(),
		CombatInput.getSpecialCooldownPercent()
	)

	-- Update round timer
	if roundTimeRemaining > 0 then
		roundTimeRemaining = math.max(0, roundTimeRemaining - dt)
		HUD.updateRoundTimer(`Time: {math.floor(roundTimeRemaining)}s`)
	end
end)

print(`[Client] {player.Name} Dragon Warz client ready!`)
