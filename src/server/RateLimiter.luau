--!strict
-- Per-player remote rate limiter.
-- Drops calls that exceed N per second per player BEFORE the handler runs.
--
-- Why this exists separately from cooldown checks: a malicious client can
-- spam FireBreath at 1000/sec. CombatManager.canFireBreath rejects them all
-- via cooldown, but we still pay the cost of 1000 cone-collision checks per
-- second per attacker. That's how a single exploiter can DoS the server.
--
-- This module enforces a hard cap per remote per player. The shape is one
-- counter per (userId, remoteName) pair, decremented every second. Cheap
-- enough to call on every remote firing — O(1) lookup, two table writes.
--
-- Usage from init.server.luau:
--   local RateLimiter = require(script.RateLimiter)
--   local OK = RateLimiter.check(player, "FireBreath", 5) -- 5 calls/sec cap
--   if not OK then return end

local Players = game:GetService("Players")

local RateLimiter = {}

-- counters[userId][remoteName] = { count: number, windowStart: number }
local counters: { [number]: { [string]: { count: number, windowStart: number } } } = {}

-- Track repeated offenders for logging (and potential auto-kick later).
-- Per-player counter of how many times they've been rate-limited in this
-- session. Logs once on hit, then every 50 hits to avoid log spam.
local violations: { [number]: number } = {}

function RateLimiter.check(player: Player, remoteName: string, callsPerSecond: number): boolean
	local userId = player.UserId
	local now = tick()

	local playerCounters = counters[userId]
	if not playerCounters then
		playerCounters = {}
		counters[userId] = playerCounters
	end

	local entry = playerCounters[remoteName]
	if not entry or (now - entry.windowStart) >= 1.0 then
		-- Fresh window
		playerCounters[remoteName] = { count = 1, windowStart = now }
		return true
	end

	-- Within the 1-second window
	if entry.count < callsPerSecond then
		entry.count += 1
		return true
	end

	-- Exceeded cap
	violations[userId] = (violations[userId] or 0) + 1
	local v = violations[userId]
	-- Log on first hit per player, then every 50th to avoid spamming Output.
	-- High-frequency violations strongly suggest an exploit attempt rather
	-- than legitimate input.
	if v == 1 or v % 50 == 0 then
		warn(`[RateLimiter] {player.Name} exceeded {remoteName} cap ({callsPerSecond}/s) — total violations this session: {v}`)
	end
	return false
end

-- Cleanup on player leave so the tables don't grow unboundedly across long
-- server lifetimes.
Players.PlayerRemoving:Connect(function(player: Player)
	counters[player.UserId] = nil
	violations[player.UserId] = nil
end)

return RateLimiter
