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

-- Sprint 7: per-dragon stat upgrade levels. Each entry is a count in [0, 5]
-- of how many times the kid has spent coins to upgrade that stat for that
-- dragon. The actual gameplay magnitude is computed by DragonProgression
-- (counts × per-stat magnitude) so we can rebalance numbers without
-- migrating saved data.
--
-- Per-dragon (not shared) by design: gives each dragon a sense of identity
-- and creates ongoing reasons to use coins beyond unlocking new dragons.
-- See ROADMAP Sprint 7 — "Mastery" cross-dragon scaling is intentionally
-- deferred until playtest data shows whether rebuild-pain is real.
export type DragonUpgradeLevels = {
	atk: number,
	def: number,
	spd: number,
	special: number,
}

export type PlayerData = {
	coins: number,
	unlockedDragons: { [string]: boolean },
	selectedDragon: string,
	stats: {
		totalKills: number,
		totalDeaths: number,
		gamesPlayed: number,
		-- Sprint 10: count of Mega Bosses (Blaze and Stage 1.5 reskins)
		-- the player has personally damaged before death. Persistent
		-- bragging-rights badge — visible in the B menu later as
		-- "Bosses Defeated: N." Underrated retention hook per peer audit.
		bossesDefeated: number,
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
	-- Sprint 7: per-dragon stat upgrade levels. Keys are dragonIds matching
	-- DragonConfig (Ember/Frost/Storm/Terra/Shadow/Prism). Missing keys are
	-- treated as all-zeros — no need to pre-populate every dragon at signup.
	dragonUpgrades: { [string]: DragonUpgradeLevels },
	-- Sprint 7: first-time tutorial flag. Flipped to true after the kid's
	-- first ProximityPrompt trigger on the Lair Stat Stone so the 5-sec
	-- intro hint doesn't replay on subsequent visits.
	hasSeenLairTutorial: boolean,
}

local DEFAULT_DATA: PlayerData = {
	coins = 0,
	unlockedDragons = { Ember = true, Frost = true },
	selectedDragon = "Ember",
	stats = { totalKills = 0, totalDeaths = 0, gamesPlayed = 0, bossesDefeated = 0 },
	lastLoginDay = 0,
	loginStreak = 0,
	lastWinDay = 0,
	totalLogins = 0,
	welcomeBonus = nil,
	-- Sprint 7: empty upgrade map — DragonProgression treats missing keys as
	-- all-zeros so we don't need to enumerate every dragon up front.
	dragonUpgrades = {},
	hasSeenLairTutorial = false,
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
			bossesDefeated = 0,
		},
		lastLoginDay = 0,
		loginStreak = 0,
		lastWinDay = 0,
		totalLogins = 0,
		welcomeBonus = nil,
		dragonUpgrades = {},
		hasSeenLairTutorial = false,
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
