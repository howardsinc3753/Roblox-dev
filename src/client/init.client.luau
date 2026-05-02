--!strict
-- Dragon Warz — Client Entry Point
-- Wires up flight, camera, combat, and HUD systems.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

print(`[Client] {player.Name} Dragon Warz client starting...`)

-- Initialize systems
CombatInput.init()
HUD.create()

-- Current state
local currentDragonId = "Ember"

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

-- Dragon spawned/changed
spawnDragonRemote.OnClientEvent:Connect(function(dragonId: string)
	currentDragonId = dragonId
	FlightController.setDragon(dragonId)
	CombatInput.setDragon(dragonId)
	HUD.setDragon(dragonId)

	-- Enable controls once character is ready
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
end)

-- Damage dealt to someone
damagePlayerRemote.OnClientEvent:Connect(function(targetUserId: number, damage: number)
	-- Show floating damage number above the target
	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if targetPlayer and targetPlayer.Character then
		local rootPart = targetPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
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

			-- Float up and fade
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

	-- If we were the victim, show "You were eliminated"
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
end)

-- Round end
roundEndRemote.OnClientEvent:Connect(function(winnerUserId: number, scoreboard: any)
	local winner = Players:GetPlayerByUserId(winnerUserId)
	local winnerName = if winner then winner.Name else "No one"
	HUD.updateRoundTimer(`Round Over! Winner: {winnerName}`)

	FlightController.disable()
	CombatInput.disable()

	-- Re-enable after intermission
	task.delay(5, function()
		FlightController.enable()
		CombatInput.enable()
	end)
end)

-- ================================
-- HUD UPDATE LOOP
-- ================================

RunService.Heartbeat:Connect(function(dt: number)
	-- Update health from humanoid
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
