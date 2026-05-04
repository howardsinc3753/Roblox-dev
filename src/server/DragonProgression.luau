--!strict
-- Sprint 7: per-dragon stat upgrade economy.
--
-- Owns:
--   - Cost curve (how many coins each upgrade level costs)
--   - Stat magnitudes (how much each level adds to attack / defense / speed
--     / special damage)
--   - Effective-stats lookup (DragonConfig base + dragonUpgrades counts)
--   - Atomic tryUpgrade (validates coins + level cap, deducts, increments,
--     forces an immediate DataStore save)
--
-- Per-player upgrade-in-flight lock (`upgradeInFlight`) is the race-
-- condition fix from peer Claude's audit: a kid double-clicking the upgrade
-- button could otherwise pass the "have enough coins" check twice before
-- either deduction landed, ending up with negative coins. The lock
-- serializes upgrade attempts per player; concurrent attempts get rejected
-- with a `false` result instead of stomping each other.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(script.Parent.DataManager)
local DragonConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("DragonConfig"))
local PlayerDataTemplate = require(ReplicatedStorage.Shared.Modules:WaitForChild("PlayerDataTemplate"))

local DragonProgression = {}

-- Cost per next level. Index = level being PURCHASED (1 = first upgrade,
-- 5 = the max-tier upgrade). 25 first-tier is intentional: peer Claude's
-- review flagged that the original 50 was just out of reach for a kid
-- with one wave-1 clear (~30 coins). 25 guarantees the first-upgrade
-- "tasted it" moment lands inside round 1 even for cautious play. Beyond
-- that the curve climbs steeply so maxing a dragon takes many sessions.
local COST_BY_LEVEL: { number } = { 25, 100, 200, 400, 800 }

-- Stat magnitude per level. Read by getEffectiveStats() to add bonuses on
-- top of the DragonConfig base values.
--
-- Speed uses DIMINISHING RETURNS (5 / 3 / 3 / 2 / 2 = +15 max) instead of
-- a flat +5 per level. Reason: the 2024 audit flagged that flat +5 × 5
-- levels = +25 speed, which on Ember (base 50) is +50% movement = the kid
-- outruns every NPC and most player breath. Becomes the mandatory "speed
-- dragon" pick that breaks PvE pacing AND PvP balance. Curving down keeps
-- speed impactful without breaking the meta.
local ATK_PER_LEVEL = 5
local DEF_PER_LEVEL = 10
local SPECIAL_PER_LEVEL = 5
local SPD_BONUS_BY_LEVEL: { number } = { 5, 3, 3, 2, 2 } -- cumulative +15 at level 5

local MAX_LEVEL = 5

-- Per-stat-key configuration for the upgrade UI's preview text. Lets
-- DragonUpgradeUI render "Damage 15 → 20" without the client needing to
-- know the magnitude formula. Keys match PlayerDataTemplate.DragonUpgradeLevels.
DragonProgression.STAT_KEYS = { "atk", "def", "spd", "special" }
DragonProgression.MAX_LEVEL = MAX_LEVEL
DragonProgression.COST_BY_LEVEL = COST_BY_LEVEL

-- Returns the cumulative speed bonus for `level` (i.e. sum of the first
-- `level` entries of SPD_BONUS_BY_LEVEL). Lookup-by-table is faster than
-- folding for the hot CombatManager path.
local function cumulativeSpeedBonus(level: number): number
	if level <= 0 then return 0 end
	local capped = math.min(level, MAX_LEVEL)
	local sum = 0
	for i = 1, capped do
		sum += SPD_BONUS_BY_LEVEL[i]
	end
	return sum
end

-- Helper: grab (or create-and-cache) the upgrade levels record for a
-- specific dragonId on a specific player. Used by getEffectiveStats and
-- tryUpgrade. Initializes an all-zeros entry the first time we touch a
-- dragon — DataManager's deepMerge handles the migration of pre-Sprint-7
-- saves at load time, but mid-game upgrades need this defensive create.
local function getOrCreateLevels(player: Player, dragonId: string): PlayerDataTemplate.DragonUpgradeLevels?
	local data = DataManager.getData(player)
	if not data then return nil end
	local levels = data.dragonUpgrades[dragonId]
	if not levels then
		levels = { atk = 0, def = 0, spd = 0, special = 0 }
		data.dragonUpgrades[dragonId] = levels
	end
	return levels
end

-- Public: read the all-zeros-default upgrade levels for a dragon. Used by
-- the client UI (via the GetPlayerData remote) and by getEffectiveStats.
function DragonProgression.getLevels(player: Player, dragonId: string): PlayerDataTemplate.DragonUpgradeLevels
	local data = DataManager.getData(player)
	if not data then return { atk = 0, def = 0, spd = 0, special = 0 } end
	local levels = data.dragonUpgrades[dragonId]
	if not levels then return { atk = 0, def = 0, spd = 0, special = 0 } end
	return levels
end

-- Public: stat magnitudes a level WOULD add. Used by the UI's preview row
-- "Damage 15 → 20" so the kid sees what they're buying. Returns the delta
-- from `level` to `level+1` (i.e. what the next purchase grants).
function DragonProgression.previewDelta(statKey: string, fromLevel: number): number
	-- Speed has per-level diminishing returns; everything else is flat.
	if statKey == "spd" then
		local nextLevel = fromLevel + 1
		if nextLevel < 1 or nextLevel > MAX_LEVEL then return 0 end
		return SPD_BONUS_BY_LEVEL[nextLevel]
	elseif statKey == "atk" then
		return ATK_PER_LEVEL
	elseif statKey == "def" then
		return DEF_PER_LEVEL
	elseif statKey == "special" then
		return SPECIAL_PER_LEVEL
	end
	return 0
end

-- Public: cost to upgrade from `currentLevel` to `currentLevel+1`. Returns
-- nil if already at MAX_LEVEL (UI uses this to render the "MAX" badge).
function DragonProgression.getUpgradeCost(currentLevel: number): number?
	local nextLevel = currentLevel + 1
	if nextLevel < 1 or nextLevel > MAX_LEVEL then return nil end
	return COST_BY_LEVEL[nextLevel]
end

-- Public: combine DragonConfig base values + dragonUpgrades counts into
-- the actual stats the player gets in combat. Called by CombatManager
-- when initializing a player's combat state, and by client modules
-- (FlightController for upgraded speed, HUD for level display).
--
-- Returns a fresh table — caller is free to mutate it.
export type EffectiveStats = {
	health: number,
	damage: number,
	speed: number,
	specialDamage: number, -- specials currently use damage*2 etc; this is the
	                        -- explicit upgrade-aware override
	atkLevel: number,
	defLevel: number,
	spdLevel: number,
	specialLevel: number,
	totalLevel: number, -- sum of all four; HUD uses for "Lv N" display
}

function DragonProgression.getEffectiveStats(player: Player, dragonId: string): EffectiveStats
	local base = DragonConfig[dragonId]
	if not base then
		-- Fallback: unknown dragon → return Ember-equivalent zeroes so callers
		-- don't crash. Logged for diagnosis.
		warn(`[DragonProgression] Unknown dragonId={dragonId}; returning fallback stats`)
		return {
			health = 100, damage = 10, speed = 50, specialDamage = 20,
			atkLevel = 0, defLevel = 0, spdLevel = 0, specialLevel = 0, totalLevel = 0,
		}
	end
	local levels = DragonProgression.getLevels(player, dragonId)
	local atkBonus = levels.atk * ATK_PER_LEVEL
	local defBonus = levels.def * DEF_PER_LEVEL
	local spdBonus = cumulativeSpeedBonus(levels.spd)
	local specialBonus = levels.special * SPECIAL_PER_LEVEL
	return {
		health = base.health + defBonus,
		damage = base.damage + atkBonus,
		speed = base.speed + spdBonus,
		-- Specials don't have a dedicated base value in DragonConfig; combat
		-- code derives special damage from `dragon.damage` with element-
		-- specific multipliers. The "special" upgrade adds a flat bonus that
		-- combat can choose to fold into its multiplier. Combat code reads
		-- specialDamage when present.
		specialDamage = base.damage + specialBonus,
		atkLevel = levels.atk,
		defLevel = levels.def,
		spdLevel = levels.spd,
		specialLevel = levels.special,
		totalLevel = levels.atk + levels.def + levels.spd + levels.special,
	}
end

-- ===== ATOMIC UPGRADE PATH =====
-- Per-player lock so a double-click can't pass the coin check twice and
-- spend more than the kid actually has. Cleared in PlayerRemoving via the
-- public clearLock helper below.
local upgradeInFlight: { [number]: boolean } = {}

function DragonProgression.clearLock(player: Player)
	upgradeInFlight[player.UserId] = nil
end

-- Returns (success, newLevel, newCoins, errorReason).
-- errorReason is one of: nil (success), "no_data", "in_flight", "unknown_dragon",
-- "unknown_stat", "max_level", "not_enough_coins", "save_failed".
-- The remote handler in init.server.luau translates the reason into a client
-- payload so the UI can surface a useful error if needed.
function DragonProgression.tryUpgrade(player: Player, dragonId: string, statKey: string): (boolean, number?, number?, string?)
	if upgradeInFlight[player.UserId] then
		return false, nil, nil, "in_flight"
	end
	upgradeInFlight[player.UserId] = true

	-- Validation chain. Each branch sets the lock-cleared flag via the local
	-- `release()` helper before returning so an early exit doesn't leave
	-- the lock stuck. (Lua has no try/finally; this is the cleanest pattern
	-- without the multi-return-through-pcall trap.)
	local function release()
		upgradeInFlight[player.UserId] = nil
	end

	local data = DataManager.getData(player)
	if not data then release(); return false, nil, nil, "no_data" end
	if not DragonConfig[dragonId] then release(); return false, nil, nil, "unknown_dragon" end
	if statKey ~= "atk" and statKey ~= "def" and statKey ~= "spd" and statKey ~= "special" then
		release(); return false, nil, nil, "unknown_stat"
	end

	local levels = getOrCreateLevels(player, dragonId)
	if not levels then release(); return false, nil, nil, "no_data" end
	-- Bind levels-as-any to a concrete local once. Dynamic statKey index
	-- needs the `any` cast, but we want to dot-write it on its own line —
	-- and Lua parses a line starting with `(...)` as a function call on
	-- the previous expression's result. Concrete local sidesteps that.
	local levelsAny = levels :: any
	local current = levelsAny[statKey] :: number
	if current >= MAX_LEVEL then release(); return false, nil, nil, "max_level" end

	local cost = DragonProgression.getUpgradeCost(current)
	if not cost then release(); return false, nil, nil, "max_level" end
	if data.coins < cost then release(); return false, nil, nil, "not_enough_coins" end

	-- Mutate: deduct + increment + persist. All three under the lock so a
	-- concurrent attempt sees the post-deduction state, not the pre-state.
	data.coins -= cost
	levelsAny[statKey] = current + 1
	local newLevel = current + 1
	local newCoins = data.coins

	-- Force-save so a server crash or kid quit-out doesn't lose the purchase.
	-- DataStore quotas can handle our upgrade rate (a kid can't spam upgrades
	-- fast enough to exceed Roblox's 6/min/key limit). DataManager.savePlayer
	-- wraps its own pcall internally so this won't throw.
	local saved = DataManager.savePlayer(player)
	if not saved then
		-- Roll back the in-memory state so a retry stays consistent. Without
		-- this rollback, a transient DataStore failure would leave the kid
		-- with the upgrade applied locally but no DataStore record.
		-- Reuse levelsAny from above to avoid the paren-prefix parser bug.
		data.coins += cost
		levelsAny[statKey] = current
		release()
		return false, nil, nil, "save_failed"
	end

	release()
	return true, newLevel, newCoins, nil
end

-- Clean up the lock when the player leaves so a stuck flag from an
-- in-progress upgrade-at-disconnect doesn't haunt the next player on
-- the same userId in the same server (rare but possible with rejoin).
Players.PlayerRemoving:Connect(function(player: Player)
	DragonProgression.clearLock(player)
end)

return DragonProgression
