--!strict
-- Server entry point
-- This script runs when the server starts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("[Server] Game server started")

-- Player join/leave handlers
Players.PlayerAdded:Connect(function(player: Player)
	print(`[Server] {player.Name} joined`)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	print(`[Server] {player.Name} leaving`)
end)
