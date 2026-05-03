--!strict
-- Canonical list of all remote event/function names.
-- Both server and client reference this to avoid string typos.

return {
	-- Client → Server (RemoteEvents)
	SelectDragon = "SelectDragon",
	UnlockDragon = "UnlockDragon",
	FireBreath = "FireBreath",
	UseSpecial = "UseSpecial",

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

	-- Client → Server (RemoteFunctions)
	GetPlayerData = "GetPlayerData",
}
