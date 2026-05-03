--!strict
-- Canonical list of all remote event/function names.
-- Both server and client reference this to avoid string typos.

return {
	-- Client → Server (RemoteEvents)
	SelectDragon = "SelectDragon",
	UnlockDragon = "UnlockDragon",
	FireBreath = "FireBreath",
	UseSpecial = "UseSpecial",
	-- Lock-on telemetry. Client fires when its lock-on target changes (player
	-- userId, or 0 to clear). Server uses this to warn the locked player.
	LockOnTarget = "LockOnTarget",

	-- Server → Client (RemoteEvents)
	DamagePlayer = "DamagePlayer",
	PlayerKO = "PlayerKO",
	RoundStart = "RoundStart",
	RoundEnd = "RoundEnd",
	UpdateCoins = "UpdateCoins",
	SpawnDragon = "SpawnDragon",
	UpdateScoreboard = "UpdateScoreboard",
	SyncTimer = "SyncTimer",
	SpecialEffect = "SpecialEffect",
	-- NPC-specific events. Kept separate from DamagePlayer/PlayerKO so the
	-- client can render damage numbers + breath projectiles on NPC models
	-- without needing a Player object lookup.
	DamageNPC = "DamageNPC", -- Server → shooter only: hit feedback (floating number + sound)
	NPCBreathFired = "NPCBreathFired", -- Server → all: render projectile from NPC to target
	-- Server → locked-on player: brief warning flash + tick sound so they
	-- know an enemy is targeting them. Lets the victim dodge before the hit.
	LockedByEnemy = "LockedByEnemy",

	-- Client → Server (RemoteFunctions)
	GetPlayerData = "GetPlayerData",
}
