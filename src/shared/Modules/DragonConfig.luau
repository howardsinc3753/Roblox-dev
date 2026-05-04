--!strict
-- Dragon roster configuration
-- All dragon stats and metadata live here. Both server and client read this.

export type DragonStats = {
	name: string,
	element: string,
	health: number,
	speed: number,
	damage: number,
	specialName: string,
	specialCooldown: number,
	color: Color3,
	secondaryColor: Color3,
	cost: number,
	-- Optional: Roblox asset ID for a Meshy-generated dragon model.
	-- If set, DragonSpawner uses InsertService:LoadAsset() instead of placeholder parts.
	meshAssetId: number?,
	-- Scale to apply to loaded mesh (Meshy meshes often need adjustment to match Roblox studs)
	meshScale: number?,
}

local Dragons: { [string]: DragonStats } = {
	Ember = {
		name = "Ember",
		element = "Fire",
		health = 150, -- buffed from 100 (kid playtest: too fragile vs NPC waves)
		speed = 50,
		damage = 15,
		specialName = "Fireball Burst",
		specialCooldown = 10,
		color = Color3.fromRGB(255, 80, 20),
		secondaryColor = Color3.fromRGB(255, 200, 50),
		cost = 0,
		meshAssetId = 115289268931347, -- Meshy-generated Ember (refined + remeshed)
		meshScale = 4, -- tweak this if dragon appears too small/large
	},
	Frost = {
		name = "Frost",
		element = "Ice",
		health = 180, -- buffed from 120 (kid playtest balance pass)
		speed = 40,
		damage = 12,
		specialName = "Frost Shield", -- renamed from Ice Wall for kid-clarity (it's a defensive heal)
		specialCooldown = 10,
		color = Color3.fromRGB(100, 180, 255),
		secondaryColor = Color3.fromRGB(220, 240, 255),
		cost = 0,
		meshAssetId = 112674581463196, -- Meshy-generated Frost dragon
		meshScale = 4, -- match Ember; tweak if proportions look off
	},
	Storm = {
		name = "Storm",
		element = "Lightning",
		health = 120, -- buffed from 80 (kid playtest balance pass)
		speed = 60,
		damage = 18,
		specialName = "Chain Lightning",
		specialCooldown = 10,
		color = Color3.fromRGB(255, 255, 50),
		secondaryColor = Color3.fromRGB(150, 80, 255),
		cost = 100,
		meshAssetId = 118836377435399, -- Meshy lightning storm dragon
		meshScale = 4,
	},
	Terra = {
		name = "Terra",
		element = "Earth",
		health = 220, -- buffed from 150 (kid playtest; Terra is the tank, lean into it)
		speed = 35,
		damage = 10,
		specialName = "Rock Armor",
		specialCooldown = 10,
		color = Color3.fromRGB(139, 119, 80),
		secondaryColor = Color3.fromRGB(80, 160, 60),
		cost = 150,
		meshAssetId = 133112860627881, -- Meshy earth/terra dragon
		meshScale = 4,
	},
	Shadow = {
		name = "Shadow",
		element = "Dark",
		health = 135, -- buffed from 90 (kid playtest balance pass)
		speed = 55,
		damage = 14,
		specialName = "Invisibility",
		specialCooldown = 10,
		color = Color3.fromRGB(60, 20, 80),
		secondaryColor = Color3.fromRGB(150, 50, 200),
		cost = 200,
		meshAssetId = 87676231942895, -- Meshy sinister/shadow dragon
		meshScale = 4,
	},
	Prism = {
		name = "Prism",
		element = "Light",
		health = 150, -- buffed from 100 (kid playtest balance pass)
		speed = 50,
		damage = 13,
		specialName = "Heal Pulse",
		specialCooldown = 10,
		color = Color3.fromRGB(255, 255, 255),
		secondaryColor = Color3.fromRGB(255, 200, 255),
		cost = 300,
		meshAssetId = 117898729145232, -- Meshy prism/light dragon
		meshScale = 4,
	},
}

return Dragons
