--!strict
-- Creates all RemoteEvents and RemoteFunctions in ReplicatedStorage.
-- Run once on server startup before anything else references them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteNames = require(ReplicatedStorage.Shared.Network:WaitForChild("RemoteNames"))

local function setup()
	local remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage

	-- Create RemoteEvents
	local eventNames = {
		RemoteNames.SelectDragon,
		RemoteNames.UnlockDragon,
		RemoteNames.FireBreath,
		RemoteNames.UseSpecial,
		RemoteNames.DamagePlayer,
		RemoteNames.PlayerKO,
		RemoteNames.RoundStart,
		RemoteNames.RoundEnd,
		RemoteNames.UpdateCoins,
		RemoteNames.SpawnDragon,
		RemoteNames.UpdateScoreboard,
		RemoteNames.SyncTimer,
		RemoteNames.SpecialEffect,
		RemoteNames.DamageNPC,
		RemoteNames.NPCBreathFired,
		RemoteNames.LockOnTarget,
		RemoteNames.LockedByEnemy,
		RemoteNames.UseShield,
		RemoteNames.ShieldActivated,
		RemoteNames.WaveStateChanged,
		RemoteNames.UpgradeStat,
		RemoteNames.DragonStatsUpdated,
		RemoteNames.DummyHit,
		RemoteNames.MarkLairTutorialSeen,
		RemoteNames.MarkBossTutorialSeen,
		RemoteNames.BossTelegraph,
		RemoteNames.BossAttackImpact,
		RemoteNames.BossMusicState,
		RemoteNames.BossBannerState,
	}

	for _, name in eventNames do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotesFolder
	end

	-- Create RemoteFunctions
	local functionNames = {
		RemoteNames.GetPlayerData,
	}

	for _, name in functionNames do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = remotesFolder
	end

	return remotesFolder
end

return { setup = setup }
