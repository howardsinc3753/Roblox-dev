--!strict
-- Default player data template
-- Used by the server to initialize new players and by both sides for type checking.

export type PlayerData = {
	coins: number,
	unlockedDragons: { [string]: boolean },
	selectedDragon: string,
	stats: {
		totalKills: number,
		totalDeaths: number,
		gamesPlayed: number,
	},
}

local DEFAULT_DATA: PlayerData = {
	coins = 0,
	unlockedDragons = { Ember = true, Frost = true },
	selectedDragon = "Ember",
	stats = { totalKills = 0, totalDeaths = 0, gamesPlayed = 0 },
}

-- Deep copy so each player gets their own table
local function getDefault(): PlayerData
	return {
		coins = DEFAULT_DATA.coins,
		unlockedDragons = {
			Ember = true,
			Frost = true,
		},
		selectedDragon = DEFAULT_DATA.selectedDragon,
		stats = {
			totalKills = 0,
			totalDeaths = 0,
			gamesPlayed = 0,
		},
	}
end

return {
	DEFAULT = DEFAULT_DATA,
	getDefault = getDefault,
}
