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
		damage = 8,
		detectionRange = 120,
		attackRange = 60,
		attackCooldown = 2.0,
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
		damage = 15,
		detectionRange = 150,
		attackRange = 75,
		attackCooldown = 1.5,
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
		damage = 25,
		detectionRange = 200,
		attackRange = 90,
		attackCooldown = 1.2,
		coinReward = 30,
		color = Color3.fromRGB(180, 30, 30),
		secondaryColor = Color3.fromRGB(255, 100, 50),
		scale = 1.5,
		meshAssetId = 133112860627881, -- Terra dragon (chunky/tank look)
		meshScale = 6,
	},
}

return Enemies
