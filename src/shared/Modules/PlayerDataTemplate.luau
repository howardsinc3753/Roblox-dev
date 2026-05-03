--!strict
-- Default player data template
-- Used by the server to initialize new players and by both sides for type checking.

-- Transient bonus payload populated server-side once per login session.
-- Lives in PlayerData (not its own remote) so the client picks it up via the
-- existing GetPlayerData refresh on join. The client shows the banner once,
-- then ignores subsequent refreshes via a local "shown this session" flag.
export type WelcomeBonus = {
	streak: number, -- consecutive days played including today
	dailyCoins: number, -- flat daily login bonus (10)
	streakCoins: number, -- streak bonus (min(streak, 5) * 5; cap 25)
	totalCoins: number, -- dailyCoins + streakCoins; what we just added to balance
	firstWinAvailable: boolean, -- true if "first win of day" reward not yet claimed
}

export type PlayerData = {
	coins: number,
	unlockedDragons: { [string]: boolean },
	selectedDragon: string,
	stats: {
		totalKills: number,
		totalDeaths: number,
		gamesPlayed: number,
	},
	-- Retention tracking. Days are stored as integers in YYYYMMDD form (UTC)
	-- so comparisons are fast and time-zone independent.
	lastLoginDay: number, -- e.g. 20260503; 0 = never logged in
	loginStreak: number, -- consecutive days; 0 for a fresh account
	lastWinDay: number, -- last day "first win of day" bonus was claimed
	totalLogins: number, -- lifetime count (reserved for achievements)
	-- Set by server on login, cleared by client after banner renders. Optional
	-- because subsequent GetPlayerData refreshes during the same session will
	-- still see the value but client tracks "already shown" locally.
	welcomeBonus: WelcomeBonus?,
}

local DEFAULT_DATA: PlayerData = {
	coins = 0,
	unlockedDragons = { Ember = true, Frost = true },
	selectedDragon = "Ember",
	stats = { totalKills = 0, totalDeaths = 0, gamesPlayed = 0 },
	lastLoginDay = 0,
	loginStreak = 0,
	lastWinDay = 0,
	totalLogins = 0,
	welcomeBonus = nil,
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
		lastLoginDay = 0,
		loginStreak = 0,
		lastWinDay = 0,
		totalLogins = 0,
		welcomeBonus = nil,
	}
end

return {
	DEFAULT = DEFAULT_DATA,
	getDefault = getDefault,
}
