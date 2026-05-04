--!strict
-- Canonical list of all remote event/function names.
-- Both server and client reference this to avoid string typos.

return {
	-- Client → Server (RemoteEvents)
	SelectDragon = "SelectDragon",
	UnlockDragon = "UnlockDragon",
	FireBreath = "FireBreath",
	UseSpecial = "UseSpecial",
	-- Defensive shield bubble (R key / X button on gamepad). Server validates
	-- cooldown and broadcasts ShieldActivated so all clients render the visual.
	UseShield = "UseShield",
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
	-- Server → all: someone activated their shield. Client renders the
	-- defensive bubble around that player's dragon for SHIELD_DURATION sec.
	ShieldActivated = "ShieldActivated",
	-- NPC-specific events. Kept separate from DamagePlayer/PlayerKO so the
	-- client can render damage numbers + breath projectiles on NPC models
	-- without needing a Player object lookup.
	DamageNPC = "DamageNPC", -- Server → shooter only: hit feedback (floating number + sound)
	NPCBreathFired = "NPCBreathFired", -- Server → all: render projectile from NPC to target
	-- Server → locked-on player: brief warning flash + tick sound so they
	-- know an enemy is targeting them. Lets the victim dodge before the hit.
	LockedByEnemy = "LockedByEnemy",
	-- Sprint 6: wave state machine. Server fires when a wave transitions
	-- between INCOMING (telegraph) → ACTIVE (fighting) → CLEARED/TIMEOUT
	-- → RESTING (countdown to next). Drives the WaveTracker HUD on the
	-- client so kids see structured wave progress instead of continuous
	-- chaos. Payload is a Variant table specific to each state.
	WaveStateChanged = "WaveStateChanged",

	-- Client → Server (RemoteFunctions)
	GetPlayerData = "GetPlayerData",
}
