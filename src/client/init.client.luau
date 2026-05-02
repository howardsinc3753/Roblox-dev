--!strict
-- Client entry point
-- This script runs on each player's client

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

print(`[Client] {player.Name} client started`)
