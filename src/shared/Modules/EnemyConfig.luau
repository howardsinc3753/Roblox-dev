--!strict
-- Enemy NPC configuration. Defines tiered hostile dragons that spawn in waves
-- and attack players. Separate from DragonConfig (which is player-only) so
-- enemy balancing can be tuned without touching player progression.

export type EnemyStats = {
	name: string,
	tier: string, -- "Scout" | "Warrior" | "Boss"
	health: number,
	speed: number, -- studs/sec
	damage: number,
	detectionRange: number, -- studs; how far it spots players
	attackRange: number, -- studs; how close before firing breath
	attackCooldown: number, -- seconds between breath attacks
	coinReward: number, -- coins given to whoever kills it
	color: Color3, -- body color for placeholder model + trail
	secondaryColor: Color3, -- accent color
	scale: number, -- visual scale; bosses are bigger
	-- Optional Roblox mesh asset ID. If nil, uses placeholder Part-based model.
	-- For MVP we reuse player dragon meshes — gives variety without new assets.
	meshAssetId: number?,
	meshScale: number?,
}

local Enemies: { [string]: EnemyStats } = {
	-- Scouts: fast, weak, swarm in numbers. Cannon fodder for early-round threat.
	Scout = {
		name = "Wraith Scout",
		tier = "Scout",
		health = 50,
		speed = 45,
		damage = 4, -- nerfed from 6 (kid playtest: wave dps too lethal)
		detectionRange = 120,
		attackRange = 60,
		attackCooldown = 2.5, -- slowed from 2.0 (more dodge windows)
		coinReward = 5,
		color = Color3.fromRGB(80, 40, 100),
		secondaryColor = Color3.fromRGB(160, 80, 200),
		scale = 0.7,
		meshAssetId = 87676231942895, -- Shadow dragon (sinister)
		meshScale = 3,
	},
	-- Warriors: balanced threat, mid-round spawns. Real fights.
	Warrior = {
		name = "Storm Warrior",
		tier = "Warrior",
		health = 120,
		speed = 40,
		damage = 8, -- nerfed from 11 (kid playtest)
		detectionRange = 150,
		attackRange = 75,
		attackCooldown = 2.2, -- slowed from 1.8
		coinReward = 12,
		color = Color3.fromRGB(80, 80, 200),
		secondaryColor = Color3.fromRGB(150, 80, 255),
		scale = 1.0,
		meshAssetId = 118836377435399, -- Storm dragon
		meshScale = 4,
	},
	-- Bosses: rare, dangerous, huge coin reward. Late-round waves.
	Boss = {
		name = "Ancient Wyrm",
		tier = "Boss",
		health = 250,
		speed = 35,
		damage = 12, -- nerfed from 18 (kid playtest: bosses one-shot strategy too punishing)
		detectionRange = 200,
		attackRange = 90,
		attackCooldown = 2.0, -- slowed from 1.5
		coinReward = 30,
		color = Color3.fromRGB(180, 30, 30),
		secondaryColor = Color3.fromRGB(255, 100, 50),
		scale = 1.5,
		meshAssetId = 133112860627881, -- Terra dragon (chunky/tank look)
		meshScale = 6,
	},
	-- Sprint 10: Mega Boss tier — BLAZE THE INFERNO LORD. Spawns once per
	-- Mega-Boss-Round (every 3rd round). HP scales by player count at
	-- spawn (not stored here — BossManager.spawnBlaze multiplies the base).
	-- Telegraphed attacks (Inferno Slam circle + Magma Beam line) replace
	-- the standard NPC AI breath; the regular `damage` field below applies
	-- ONLY to those telegraphed attacks. coinReward here is the total pool
	-- distributed by damage contribution (see BossManager death payout).
	-- Visual: Storm dragon mesh upscaled to scale 12, deep-red tint.
	-- Replaces a custom mesh upload for MVP — Stage 1.5 may swap to a
	-- bespoke Blaze model.
	Blaze = {
		name = "Blaze the Inferno Lord",
		tier = "MegaBoss",
		health = 800, -- BASE HP; BossManager multiplies by playerCount at spawn
		speed = 25, -- slower than regular bosses — kids need to be able to disengage
		damage = 25, -- per telegraphed attack hit; not used for auto-breath
		detectionRange = 250,
		attackRange = 80, -- Inferno Slam range; beam goes farther via separate const
		attackCooldown = 5, -- between attack telegraphs
		coinReward = 300, -- damage-share pool (50 flat participation paid separately)
		color = Color3.fromRGB(200, 30, 20), -- deep red signature
		secondaryColor = Color3.fromRGB(255, 140, 40),
		scale = 3.0,
		-- Sprint 10 Tier 3: dedicated fierce-dragon Meshy boss model.
		-- Replaces the Storm-dragon-upscaled placeholder. Generated from
		-- the four-legged classic-dragon prompt (option 1: spikes,
		-- magma veins, curved horns, spiked tail club).
		meshAssetId = 130983798052135,
		-- meshScale 12 worked for the upscaled Storm placeholder; the
		-- new dedicated Meshy mesh may have a different natural size.
		-- Tune in playtest if Blaze looks too big/small. Lowering by
		-- 30-50% is common after a Meshy mesh swap; raising rare.
		meshScale = 12,
	},
}

return Enemies
