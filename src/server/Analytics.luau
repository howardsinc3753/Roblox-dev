--!strict
-- Sprint 9a: server-side wrapper around Roblox's AnalyticsService.
--
-- Why this module exists:
-- - Single owner of the event taxonomy. Renaming an event (or adding a
--   field) happens in one place; callers stay clean. Without this we'd
--   end up with AnalyticsService calls scattered across init.server,
--   NPCManager, DragonProgression, RoundManager, etc. — and any rename
--   would mean find-and-replace across the whole codebase.
-- - Per-player session bookkeeping (sessionId, joinTime). Roblox's
--   AnalyticsService doesn't carry session context across events; we
--   inject it via customFields so every event belongs to a session
--   the dashboard can group by.
-- - Defensive wrapping. AnalyticsService can throw in some edge cases
--   (e.g., experimental settings, kicked players). pcall every call
--   here so a logging failure NEVER takes down a gameplay path.
--
-- Event taxonomy (Sprint 9a):
--   SessionStart       — player joined; begins their funnel
--   WaveCleared        — player was alive in Arena when wave N cleared
--   RoundWon           — round ended and this player was the winner
--   RoundCompleted     — round ended (winner or not) — captures
--                        non-winners too so we can compute participation
--                        rate vs. solo skip-out
--   StatUpgraded       — kid spent coins on a stat upgrade
--   DragonUnlocked     — kid spent coins to unlock a new dragon
--
-- Event taxonomy (Sprint 10 placeholders, fired but currently unused):
--   BossEncountered    — Mega Boss spawned in this round
--   BossDefeated       — Mega Boss died (player damaged it before death)
--   BossTimedOut       — Mega Boss despawned after the 30s warning
--                        without being killed
--
-- Funnel computed from these events:
--   Joined → First Wave Cleared → First Round Won → First Stat Upgrade →
--   First Dragon Unlocked → First Boss Defeated
-- Each transition rate is a number that tells us where kids drop off.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Analytics = {}

-- Per-player session record. Created at SessionStart, cleaned up in
-- PlayerRemoving via Analytics.endSession(). Keyed by userId.
type SessionRecord = {
	sessionId: string,
	joinTimeOs: number, -- os.time() at session start, for elapsed calc
}

local sessions: { [number]: SessionRecord } = {}

-- Studio gates: we don't want test events polluting production analytics.
-- AnalyticsService also doesn't replicate to the dashboard from Studio
-- runs anyway, but explicit gate documents intent + makes log lines clear.
local IS_STUDIO = RunService:IsStudio()

-- Generate a session ID. Roblox doesn't provide one; we build a stable
-- per-session string from userId + epoch seconds + a random suffix so
-- two simultaneous joins don't collide.
local function newSessionId(userId: number): string
	local now = os.time()
	local suffix = math.random(1000, 9999)
	return string.format("%d-%d-%d", userId, now, suffix)
end

-- Internal: fire a custom event with session context attached. All
-- gameplay-visible callers route through this. Wrapped in pcall so a
-- transient AnalyticsService failure (thrown from an obscure edge case)
-- never propagates into the gameplay path that called us.
local function fireEvent(player: Player, eventName: string, value: number, customFields: { [string]: any }?)
	if not player or not player.Parent then return end
	local session = sessions[player.UserId]
	local fields: { [string]: any } = customFields or {}
	if session then
		fields.sessionId = session.sessionId
		fields.elapsedSec = os.time() - session.joinTimeOs
	end

	if IS_STUDIO then
		-- Mirror to Output console so devs can see the event flow during
		-- Studio playtest without needing the live dashboard. Dashboard
		-- in Studio is a no-op anyway.
		print(`[Analytics][studio] {eventName} userId={player.UserId} value={value} fields={fields}`)
		return
	end

	local ok, err = pcall(function()
		-- LogCustomEvent is the workhorse for arbitrary events. Roblox's
		-- dashboard groups by eventName + lets you filter by customFields.
		-- numeric `value` is the primary metric column.
		AnalyticsService:LogCustomEvent(player, eventName, value, fields)
	end)
	if not ok then
		warn(`[Analytics] LogCustomEvent failed for {eventName}: {err}`)
	end
end

-- ===== Public API: gameplay event hooks =====

function Analytics.startSession(player: Player)
	local sessionId = newSessionId(player.UserId)
	sessions[player.UserId] = {
		sessionId = sessionId,
		joinTimeOs = os.time(),
	}
	-- Step 1 of the onboarding funnel. Subsequent events use the same
	-- sessionId so the dashboard can group "this kid's session arc."
	fireEvent(player, "SessionStart", 1, { isFirstSession = false })
	-- isFirstSession is left false here because we don't know yet —
	-- DataManager.processLogin sets data.totalLogins. The caller can
	-- enrich the field by calling Analytics.markFirstSession(player)
	-- after loadPlayer if totalLogins == 1. Keeping it as a separate
	-- call avoids coupling Analytics to DataManager's load order.
end

function Analytics.markFirstSession(player: Player)
	-- Fired once per kid's first-ever join. Lets the dashboard
	-- distinguish brand-new players from returning players in the same
	-- "SessionStart" stream.
	fireEvent(player, "FirstSession", 1, {})
end

function Analytics.endSession(player: Player)
	local session = sessions[player.UserId]
	if session then
		local sessionLength = os.time() - session.joinTimeOs
		fireEvent(player, "SessionEnd", sessionLength, {})
	end
	sessions[player.UserId] = nil
end

function Analytics.waveCleared(player: Player, waveNum: number, clearTimeSec: number, isBossWave: boolean)
	fireEvent(player, "WaveCleared", waveNum, {
		clearTimeSec = math.floor(clearTimeSec),
		isBossWave = isBossWave,
	})
end

function Analytics.roundCompleted(player: Player, roundNum: number, didWin: boolean, kills: number, coinsEarned: number)
	fireEvent(player, "RoundCompleted", roundNum, {
		didWin = didWin,
		kills = kills,
		coinsEarned = coinsEarned,
	})
	if didWin then
		fireEvent(player, "RoundWon", roundNum, { kills = kills })
	end
end

function Analytics.statUpgraded(player: Player, dragonId: string, statKey: string, newLevel: number, coinsCost: number)
	-- value = newLevel so the dashboard can chart "level distribution
	-- across player base." customFields keep the discrete dimensions
	-- (which dragon, which stat).
	fireEvent(player, "StatUpgraded", newLevel, {
		dragonId = dragonId,
		statKey = statKey,
		coinsCost = coinsCost,
	})
end

function Analytics.dragonUnlocked(player: Player, dragonId: string, coinsCost: number, viaShop: boolean)
	-- viaShop will become true in Sprint 9 (or later) when the Robux
	-- "Unlock All Dragons" pass fires this. For now coins-purchased
	-- unlocks always pass viaShop=false.
	fireEvent(player, "DragonUnlocked", coinsCost, {
		dragonId = dragonId,
		viaShop = viaShop,
	})
end

-- ===== Sprint 10 placeholders (scaffolding so dashboards can be
-- configured before Boss Waves ships). Calling these now is a no-op
-- visible only in Studio output — the dashboard sees the events on
-- the day Sprint 10 lands.

function Analytics.bossEncountered(player: Player, bossName: string, roundNum: number)
	fireEvent(player, "BossEncountered", roundNum, { bossName = bossName })
end

function Analytics.bossDefeated(player: Player, bossName: string, roundNum: number, damageContribution: number, coinReward: number)
	fireEvent(player, "BossDefeated", roundNum, {
		bossName = bossName,
		damageContribution = damageContribution,
		coinReward = coinReward,
	})
end

function Analytics.bossTimedOut(player: Player, bossName: string, roundNum: number, hpRemainingPercent: number)
	fireEvent(player, "BossTimedOut", roundNum, {
		bossName = bossName,
		hpRemainingPercent = hpRemainingPercent,
	})
end

-- Auto-cleanup so a player who disconnects without going through
-- Analytics.endSession (e.g. server crash mid-game) doesn't leak their
-- session record.
Players.PlayerRemoving:Connect(function(player: Player)
	-- endSession itself fires SessionEnd + clears the table. Calling it
	-- defensively in case init.server.luau forgot to wire it up.
	if sessions[player.UserId] then
		Analytics.endSession(player)
	end
end)

return Analytics
