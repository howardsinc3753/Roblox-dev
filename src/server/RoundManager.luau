--!strict
-- Manages game rounds: timing, scoring, transitions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundManager = {}

export type RoundState = {
	active: boolean,
	roundNumber: number,
	timeRemaining: number,
	-- Per-player round score. `roundCoins` is the running total of coins
	-- earned during THIS round only (kills + NPC kills + pickups). Used by
	-- the round-end summary so kids see their full earnings, not just the
	-- 5-coin participation bonus. Reset to 0 on round start.
	scores: { [number]: { kills: number, deaths: number, roundCoins: number } },
}

local state: RoundState = {
	active = false,
	roundNumber = 0,
	timeRemaining = 0,
	scores = {},
}

local ROUND_DURATION = 120 -- seconds
local INTERMISSION_DURATION = 15 -- seconds

-- Callbacks set by init.server.luau
local onRoundStart: (() -> ())?
local onRoundEnd: (() -> ())?

function RoundManager.setCallbacks(startCb: () -> (), endCb: () -> ())
	onRoundStart = startCb
	onRoundEnd = endCb
end

function RoundManager.getState(): RoundState
	return state
end

function RoundManager.isActive(): boolean
	return state.active
end

function RoundManager.initPlayerScore(player: Player)
	state.scores[player.UserId] = { kills = 0, deaths = 0, roundCoins = 0 }
end

-- Track coins earned this round. Called from every coin-grant point during
-- the round (PvP kills, NPC kills, future pickups). Reset to 0 on round
-- start. Powers the "+N coins earned" line in RoundEndSummary.
function RoundManager.recordCoins(player: Player, amount: number)
	local score = state.scores[player.UserId]
	if score then
		score.roundCoins += amount
	end
end

function RoundManager.getRoundCoins(player: Player): number
	local score = state.scores[player.UserId]
	return if score then score.roundCoins else 0
end

function RoundManager.removePlayerScore(player: Player)
	state.scores[player.UserId] = nil
end

function RoundManager.recordKill(killer: Player, victim: Player)
	local killerScore = state.scores[killer.UserId]
	if killerScore then
		killerScore.kills += 1
	end

	local victimScore = state.scores[victim.UserId]
	if victimScore then
		victimScore.deaths += 1
	end
end

-- NPC kills also count toward the round score so kids fighting waves see
-- a non-zero kill count at round end (kid playtest: "0 Kills" feedback was
-- from killing only NPCs, not players). No victim score to deduct since
-- NPCs aren't tracked here — server.NPCManager owns that lifecycle.
function RoundManager.recordNPCKill(killer: Player)
	local killerScore = state.scores[killer.UserId]
	if killerScore then
		killerScore.kills += 1
	end
end

function RoundManager.getScoreboard(): { { userId: number, name: string, kills: number, deaths: number } }
	local board = {}
	for userId, score in state.scores do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(board, {
				userId = userId,
				name = player.Name,
				kills = score.kills,
				deaths = score.deaths,
			})
		end
	end
	-- Sort by kills descending
	table.sort(board, function(a, b)
		return a.kills > b.kills
	end)
	return board
end

function RoundManager.getWinner(): Player?
	local bestUserId: number? = nil
	local bestKills = -1

	for userId, score in state.scores do
		if score.kills > bestKills then
			bestKills = score.kills
			bestUserId = userId
		end
	end

	if bestUserId then
		return Players:GetPlayerByUserId(bestUserId)
	end
	return nil
end

-- Main round loop (runs in a spawned thread)
function RoundManager.startLoop()
	task.spawn(function()
		while true do
			-- Intermission
			state.active = false
			print(`[RoundManager] Intermission ({INTERMISSION_DURATION}s)`)
			task.wait(INTERMISSION_DURATION)

			-- Check minimum players
			if #Players:GetPlayers() < 1 then
				print("[RoundManager] Not enough players, waiting...")
				while #Players:GetPlayers() < 1 do
					task.wait(2)
				end
			end

			-- Start round
			state.roundNumber += 1
			state.active = true
			state.timeRemaining = ROUND_DURATION

			-- Reset scores
			for userId, score in state.scores do
				score.kills = 0
				score.deaths = 0
				score.roundCoins = 0 -- fresh per-round earnings count
			end

			print(`[RoundManager] Round {state.roundNumber} starting!`)
			if onRoundStart then
				onRoundStart()
			end

			-- Countdown
			while state.timeRemaining > 0 and state.active do
				task.wait(1)
				state.timeRemaining -= 1
			end

			-- End round
			state.active = false
			print(`[RoundManager] Round {state.roundNumber} ended!`)
			if onRoundEnd then
				onRoundEnd()
			end
		end
	end)
end

return RoundManager
