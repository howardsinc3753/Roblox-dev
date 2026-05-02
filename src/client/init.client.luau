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

print(`[Client] {player.Name} Dragon Warz client starting...`)

-- Initialize systems
CombatInput.init()
HUD.create()
SoundManager.init()

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
	SoundManager.play("Coin")
end)

-- Damage dealt to someone
damagePlayerRemote.OnClientEvent:Connect(function(targetUserId: number, damage: number)
	SoundManager.play("Hit")

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if targetPlayer and targetPlayer.Character then
		local rootPart = targetPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			-- Floating damage number
			local billboardGui = Instance.new("BillboardGui")
			billboardGui.Size = UDim2.fromOffset(100, 40)
			billboardGui.StudsOffset = Vector3.new(math.random(-2, 2), 6, 0)
			billboardGui.Adornee = rootPart
			billboardGui.Parent = rootPart

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
	end
end)

-- Player KO
playerKORemote.OnClientEvent:Connect(function(killerUserId: number, victimUserId: number)
	local killer = Players:GetPlayerByUserId(killerUserId)
	local victim = Players:GetPlayerByUserId(victimUserId)
	local killerName = if killer then killer.Name else "???"
	local victimName = if victim then victim.Name else "???"

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

-- Round start
local roundTimeRemaining = 0
roundStartRemote.OnClientEvent:Connect(function(roundNumber: number, duration: number)
	roundTimeRemaining = duration
	HUD.updateRoundTimer(`Round {roundNumber} - {duration}s`)
	SoundManager.play("RoundStart")
	FlightController.enable()
	CameraController.enable()
	CombatInput.enable()
end)

-- Round end
roundEndRemote.OnClientEvent:Connect(function(winnerUserId: number, scoreboard: any)
	local winner = Players:GetPlayerByUserId(winnerUserId)
	local winnerName = if winner then winner.Name else "No one"
	HUD.updateRoundTimer(`Round Over! Winner: {winnerName}`)
	SoundManager.play("RoundEnd")

	FlightController.disable()
	CombatInput.disable()

	-- Re-enable only when the next round starts (not after arbitrary delay)
	-- The RoundStart event will re-enable controls
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
