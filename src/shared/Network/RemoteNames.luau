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
	-- Sprint 7: client clicks "Upgrade Atk +5 (Cost 100)" → fires this
	-- with (dragonId, statKey). Server validates coins + level cap +
	-- per-player race lock, deducts, increments, force-saves, then
	-- replies via UpdateCoins (existing) + DragonStatsUpdated (below).
	UpgradeStat = "UpgradeStat",
	-- Sprint 7: client → server, no payload. Fired the first time the
	-- kid opens the Stat Stone modal. Server flips
	-- PlayerData.hasSeenLairTutorial so the welcome hint doesn't replay
	-- on rejoin. Idempotent: subsequent fires are silent no-ops.
	MarkLairTutorialSeen = "MarkLairTutorialSeen",
	-- Sprint 10: same idempotent-flag-flip pattern for the boss-context
	-- tutorial toast. Client fires the first time it shows the "Bosses
	-- drop the biggest coin rewards" toast so the kid never sees it
	-- twice. Server flips PlayerData.hasSeenBossTutorial + force-saves.
	MarkBossTutorialSeen = "MarkBossTutorialSeen",
	-- Sprint 10: Mega Boss attack telegraph. Server fires when Blaze
	-- starts winding up an attack so the client can render a ground
	-- marker (red circle for Inferno Slam, red line preview for Magma
	-- Beam) for windupSec seconds before the hit lands. Payload:
	--   attackType: "InfernoSlam" | "MagmaBeam"
	--   originPos: Vector3 (Slam circle center / Beam origin)
	--   directionOrRadius: Vector3 (Slam: <radius, 0, 0>; Beam: unit dir)
	--   windupSec: number
	-- FireAllClients so spectators see the same telegraph.
	BossTelegraph = "BossTelegraph",
	-- Sprint 10 visual overhaul: on-impact VFX trigger. Server fires
	-- when an attack actually lands (after windup) so the client
	-- can render the explosion / camera shake / hit feedback. Separate
	-- from BossTelegraph because telegraphs are about WIND-UP and
	-- impacts are about EXECUTION — different timings, different VFX.
	-- Payload: attackType, position (where to spawn the VFX).
	BossAttackImpact = "BossAttackImpact",
	-- Sprint 10: boss music swap. Fires twice per Mega-Boss-Round — once
	-- on encounter (active=true → swap to boss theme) and once on death
	-- or timeout (active=false → restore zone music). FireAllClients.
	BossMusicState = "BossMusicState",
	-- Sprint 10: boss banner state. Drives WaveTracker's boss-specific
	-- banner ("BLAZE APPEARS" / "ESCAPING IN Ns" / "BLAZE FALLS").
	-- state: "INCOMING" | "ACTIVE" | "WARNING" | "DEFEATED" | "TIMEOUT"
	-- payload: { hpFraction?: number, secondsLeft?: number, ... }
	BossBannerState = "BossBannerState",

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
	-- Sprint 7: server → client after a successful UpgradeStat. Carries
	-- (dragonId, levels, effectiveStats) so the upgrade UI can update
	-- the panel + HUD level indicator without a GetPlayerData round-trip.
	-- Also fired on player join (after PlayerData load) so the client's
	-- caches start populated. Result includes the effective speed so
	-- FlightController can update its movement cache for the active
	-- dragon (the speed upgrade isn't visible without this).
	DragonStatsUpdated = "DragonStatsUpdated",
	-- Sprint 7: practice-dummy hit feedback. Server fires this to the
	-- shooter when their breath cone hits a tagged Lair dummy. Client
	-- renders a floating "-N" damage number above the dummy and plays
	-- the existing Hit sound. Separate from DamageNPC so the dummy
	-- isn't accidentally counted as a kill / coin reward.
	DummyHit = "DummyHit",

	-- Client → Server (RemoteFunctions)
	GetPlayerData = "GetPlayerData",
}
