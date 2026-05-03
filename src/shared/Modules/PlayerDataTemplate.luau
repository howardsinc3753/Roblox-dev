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

-- Retention tunables. Single source of truth shared by server (DataManager
-- grants the bonuses) and client (WelcomeBanner renders progress copy like
-- "X more days for max streak"). Bumping these on server alone would
-- desync the client's max-streak threshold and produce wrong UI text.
local RETENTION = {
	DAILY_LOGIN_BONUS = 10, -- flat coins for first login each day
	STREAK_BONUS_PER_DAY = 5, -- per consecutive day, capped at MAX_STREAK_FOR_BONUS
	MAX_STREAK_FOR_BONUS = 5, -- streak day at which the streak bonus caps
	FIRST_WIN_BONUS = 50, -- "first win of the day" payout, claimed once per UTC day
}

return {
	DEFAULT = DEFAULT_DATA,
	getDefault = getDefault,
	RETENTION = RETENTION,
}
