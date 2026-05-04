--!strict
-- Sprint 10: Mega Boss orchestrator. Owns BLAZE THE INFERNO LORD's
-- lifecycle within a Mega-Boss-Round. Sits parallel to NPCManager
-- (which handles the regular wave NPCs) rather than inside it because
-- Mega Bosses are different enough — telegraphed attacks instead of
-- chase+breath, damage-contribution rewards instead of last-hitter
-- coin drop, single-instance-at-a-time, locked-at-spawn HP — that
-- mixing them would over-complicate NPCManager's tickAI.
--
-- Architecture (across commits 1-7):
--   COMMIT 1 (this one) — data + skeleton: state struct, spawn/despawn,
--     damage tracking, alive flag. No AI, no telegraphs, no rewards.
--     Module loads cleanly and the boss model appears on demand.
--   COMMIT 2 — telegraph remote + client circle/line renderers
--   COMMIT 3 — NPCManager integration: every-3rd-round detection adds
--     a 4th wave that calls BossManager.spawnBlaze
--   COMMIT 4 — boss AI tick: Inferno Slam (1.8s circle telegraph) +
--     Magma Beam (1.5s line telegraph), with damage contribution
--     tracking per player on hits the kid lands on Blaze
--   COMMIT 5 — death payout (50 flat + 300 damage-share),
--     PlayerData.bossesDefeated increment, 30s timeout despawn path
--   COMMIT 6 — banner + music swap (WaveTracker integration)
--   COMMIT 7 — ROADMAP + CODE_MAP + push

local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("EnemyConfig"))

local BossManager = {}

-- Module-local state. Only one Mega Boss alive at a time (peer audit
-- guidance — single iconic boss for MVP, not a roster); using a single
-- `activeBoss` slot rather than a table is simpler and prevents the
-- "what if two spawn at once" failure mode.
export type BossState = {
	bossType: string, -- "Blaze" for now; Stage 1.5 adds Frostmaul / Voltrix
	model: Model,
	rootPart: BasePart,
	maxHealth: number,
	currentHealth: number,
	alive: boolean,
	spawnedAt: number, -- tick() at spawn for timeout calc
	-- Damage contribution per player. Populated on every NPCManager.
	-- applyDamage call against this boss in commit 4. Reward split on
	-- death uses the proportions of this map.
	damageByUser: { [number]: number },
	-- Captured player count at spawn time. Peer audit explicitly called
	-- out NOT dynamically rescaling HP if a player joins mid-fight — it
	-- becomes unbeatable — or leaves — kid feels cheated. Lock the
	-- snapshot here and use it for reference in death-payout share math.
	playerCountAtSpawn: number,
}

local activeBoss: BossState? = nil

-- ===== Public state queries =====

function BossManager.isActive(): boolean
	return activeBoss ~= nil and activeBoss.alive
end

function BossManager.getActive(): BossState?
	if activeBoss and activeBoss.alive then
		return activeBoss
	end
	return nil
end

-- ===== Mesh load (mirrors NPCManager pattern) =====
-- Cached so a Mega-Boss-Round wave 4 spawn doesn't re-download the asset
-- on every encounter. Cleared on server shutdown via Roblox's normal
-- module-state lifecycle.
local meshCache: Model? = nil

local function loadBossMesh(assetId: number): Model?
	if meshCache then
		return meshCache:Clone()
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not result then
		warn(`[BossManager] Failed to load boss mesh assetId={assetId}: {result}`)
		return nil
	end
	local container = result :: Model
	local meshContent: Model? = nil
	for _, child in container:GetChildren() do
		if child:IsA("Model") then
			meshContent = child
			break
		end
	end
	if not meshContent then
		meshContent = container
	end
	meshCache = meshContent :: Model
	container.Parent = nil
	return (meshContent :: Model):Clone()
end

-- Build the boss model: a large anchored root part + the upscaled mesh
-- visual welded on. Anchored because Blaze hovers at one position
-- (peer spec — center of arena, 50 studs up) and fires telegraphed
-- attacks; no chase AI = no LinearVelocity needed.
local function buildBossModel(bossType: string, config: any, spawnPosition: Vector3): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = `MegaBoss_{bossType}_{tick()}`

	-- Anchored root (boss doesn't move). Sized to roughly cover the
	-- mesh's bounding box so client-side hit detection has a credible
	-- target volume even before mesh load completes.
	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Size = Vector3.new(20, 16, 30) -- approximate Blaze hitbox
	body.Position = spawnPosition
	body.Color = config.color
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false -- player dragons phase through
	body.Transparency = 0.85 -- mostly invisible; mesh handles the visual
	body.Parent = model
	model.PrimaryPart = body

	-- Mesh visual. Falls back to the placeholder body if the asset
	-- fails to load (extreme edge case — InsertService is reliable in
	-- production; this guards against transient outages).
	local meshTemplate = loadBossMesh(config.meshAssetId)
	if meshTemplate then
		if meshTemplate:IsA("Model") then
			meshTemplate:ScaleTo(config.meshScale or 1)
			meshTemplate:PivotTo(body.CFrame)
		end
		meshTemplate.Name = "BossMesh"
		meshTemplate.Parent = model
		-- Anchor + weld every BasePart in the mesh to the body, then
		-- set the body Anchored. Roblox physics: an anchored assembly
		-- where one part is anchored locks the rest via the welds.
		-- Tint the mesh to the boss's deep-red color so even if the
		-- source mesh was a different element (e.g. Storm dragon), it
		-- reads visually as Blaze.
		for _, descendant in meshTemplate:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.CanCollide = false
				descendant.Massless = true
				descendant.Color = config.color
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = body
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	else
		-- Fallback: make the body opaque so the kid at least sees a
		-- giant red box where Blaze should be.
		body.Transparency = 0
	end

	-- Tag for client-side discovery (boss-specific UI like the HP bar
	-- in commit 6 reads tags via CollectionService:GetTagged).
	CollectionService:AddTag(model, "DragonWarz_MegaBoss")
	model:SetAttribute("BossType", bossType)

	model.Parent = workspace
	return model, body
end

-- ===== Spawn / despawn =====

-- Spawns Blaze at the arena center, 50 studs up. Caller passes the
-- player count to scale HP. Returns the BossState so the caller (in
-- commit 3, NPCManager's mega-boss-wave path) can monitor the fight
-- via BossManager.isActive() / await death.
--
-- Refuses to spawn if a boss is already active — single-boss-at-a-time
-- invariant. Logs and returns the existing state in that case so the
-- caller can recover.
function BossManager.spawnBlaze(playerCount: number): BossState?
	if activeBoss and activeBoss.alive then
		warn(`[BossManager] spawnBlaze called while a boss is already active; refusing`)
		return activeBoss
	end

	local config = EnemyConfig.Blaze
	if not config then
		warn(`[BossManager] EnemyConfig.Blaze missing; cannot spawn`)
		return nil
	end

	-- Player count clamped 1..4. Solo = 1× HP (peer guidance: still
	-- satisfying for solo); 4 = cap so a busy server doesn't make the
	-- fight unbeatable. Higher counts collapse to 4 for HP purposes.
	local clampedCount = math.clamp(playerCount, 1, 4)
	local maxHp = config.health * clampedCount

	-- Spawn position: center of arena (Arena lives at origin per
	-- ArenaBuilder), 50 studs up. Forces players to fly to engage.
	local spawnPosition = Vector3.new(0, 50, 0)

	local model, rootPart = buildBossModel("Blaze", config, spawnPosition)

	local state: BossState = {
		bossType = "Blaze",
		model = model,
		rootPart = rootPart,
		maxHealth = maxHp,
		currentHealth = maxHp,
		alive = true,
		spawnedAt = tick(),
		damageByUser = {},
		playerCountAtSpawn = clampedCount,
	}
	activeBoss = state

	print(`[BossManager] Blaze spawned. HP={maxHp} ({config.health} × {clampedCount} players)`)
	return state
end

-- Despawns the active boss model + clears state. Used by:
--   - commit 5 reward path (called after death payout finishes)
--   - commit 5 timeout path (no rewards distributed)
--   - emergency cleanup if RoundManager force-ends the round mid-fight
function BossManager.despawn()
	if not activeBoss then return end
	if activeBoss.model and activeBoss.model.Parent then
		activeBoss.model:Destroy()
	end
	activeBoss = nil
end

-- ===== Damage tracking (used by commits 4-5) =====

-- ===== Sprint 10 commit 5: defeat / timeout callbacks =====
-- Fires when boss HP hits 0 — reward distribution + bossesDefeated
-- persistence + analytics happen in init.server.luau's wiring. Keeps
-- BossManager focused on combat state; reward semantics belong with
-- the rest of the economy code in init.server.luau.
local onDefeatCallback: ((bossType: string, contributions: { [number]: number }, totalDamage: number) -> ())? = nil
-- Fires on the timeout despawn path — analytics + "BLAZE ESCAPES"
-- banner. No rewards (peer audit: failure is a learning loop).
local onTimeoutCallback: ((bossType: string, hpRemainingPercent: number) -> ())? = nil

function BossManager.setOnDefeatCallback(cb: (bossType: string, contributions: { [number]: number }, totalDamage: number) -> ())
	onDefeatCallback = cb
end

function BossManager.setOnTimeoutCallback(cb: (bossType: string, hpRemainingPercent: number) -> ())
	onTimeoutCallback = cb
end

-- Apply damage to the active boss. Returns (killed, actualDamage).
-- Records the userId's contribution in damageByUser so the death
-- payout can split the share pool proportionally. killerUserId is
-- the player who landed the hit; nil for environmental damage (none
-- currently exists, future-proofing).
--
-- Sprint 10 commit 5: on HP-0 detection, fires onDefeatCallback with
-- the contributions snapshot BEFORE clearing activeBoss so the
-- reward path can iterate the map. The model itself isn't despawned
-- here — the callback handles a brief death-display delay before
-- BossManager.despawn().
function BossManager.applyDamage(damage: number, killerUserId: number?): (boolean, number)
	if not activeBoss or not activeBoss.alive then
		return false, 0
	end

	activeBoss.currentHealth = math.max(0, activeBoss.currentHealth - damage)

	if killerUserId then
		local prev = activeBoss.damageByUser[killerUserId] or 0
		activeBoss.damageByUser[killerUserId] = prev + damage
	end

	if activeBoss.currentHealth <= 0 then
		activeBoss.alive = false
		if onDefeatCallback then
			-- Snapshot the contributions table + total before any other
			-- code path can clear activeBoss. Defensive copy of the map
			-- so downstream iteration is safe even if despawn() runs
			-- during the callback (it shouldn't, but the table reference
			-- would dangle if it did).
			local contributionsCopy: { [number]: number } = {}
			local totalDamage = 0
			for userId, dmg in activeBoss.damageByUser do
				contributionsCopy[userId] = dmg
				totalDamage += dmg
			end
			onDefeatCallback(activeBoss.bossType, contributionsCopy, totalDamage)
		end
		return true, damage
	end
	return false, damage
end

-- Sprint 10 commit 5: timeout-specific despawn. Fires the timeout
-- callback (analytics + banner) BEFORE clearing state, then despawns
-- the model. Distinct from the plain despawn() so a "force cleanup"
-- caller (round force-end) doesn't accidentally trigger the
-- "BOSS ESCAPED" banner — they should call despawn() directly.
function BossManager.timeoutDespawn()
	if not activeBoss then return end
	local hpPct = if activeBoss.maxHealth > 0 then activeBoss.currentHealth / activeBoss.maxHealth else 0
	if onTimeoutCallback then
		-- Pass the contributions table reference so the callback can
		-- fire per-player analytics for each kid who damaged Blaze
		-- before time ran out. Read-only on the caller side.
		onTimeoutCallback(activeBoss.bossType, hpPct)
	end
	activeBoss.alive = false -- breaks AI tick loop immediately
	BossManager.despawn()
end

-- ===== Helpers used by commit 5 reward path =====

-- Returns total damage dealt across all players. Used in the share
-- formula: each player's share = (their damage / total damage) × pool.
function BossManager.getTotalDamage(): number
	if not activeBoss then return 0 end
	local total = 0
	for _, dmg in activeBoss.damageByUser do
		total += dmg
	end
	return total
end

-- Returns the damage map directly. Caller should NOT mutate it; this is
-- a reference for read-only consumption (Lua doesn't enforce const).
function BossManager.getDamageContributions(): { [number]: number }
	if not activeBoss then return {} end
	return activeBoss.damageByUser
end

-- Player-leave hook: a player damages Blaze, then disconnects mid-fight.
-- We KEEP their damage contribution in the table — the reward payout
-- (commit 5) checks Players:GetPlayerByUserId before paying so a left
-- player's share simply doesn't get distributed. Their absence doesn't
-- penalize the remaining players (the pool is fixed at 300 + 50 per
-- still-present participant), and we don't try to retroactively pay
-- the disconnected kid. Documented for clarity rather than coded —
-- the simple "Players:GetPlayerByUserId returns nil → skip" pattern in
-- commit 5 handles it implicitly.

-- ===== Sprint 10 commit 4: combat hit detection + AI tick =====

-- Cone hit detection against the active boss. Mirrors the
-- CombatManager.findHitNPC pattern so player breath and cone specials
-- can route damage to Blaze using the same cone-test logic. Returns
-- the active BossState if the cone hits, nil otherwise.
-- Caller is responsible for applying damage via BossManager.applyDamage.
function BossManager.tryHitWithCone(origin: Vector3, direction: Vector3, dotThreshold: number, range: number): BossState?
	if not activeBoss or not activeBoss.alive then return nil end
	if direction.Magnitude < 0.001 then return nil end
	local toBoss = activeBoss.rootPart.Position - origin
	local dist = toBoss.Magnitude
	if dist > range then return nil end
	if dist < 0.001 then return activeBoss end -- inside boss hitbox
	local dot = toBoss.Unit:Dot(direction.Unit)
	if dot < dotThreshold then return nil end
	return activeBoss
end

-- Callbacks set by init.server.luau at startup. The boss AI tick uses
-- them to deal damage to players + fire telegraph remotes. Set-once
-- pattern so every spawn doesn't re-wire the callbacks.
local damageCallback: ((target: Player, damage: number, source: Vector3) -> ())? = nil
local telegraphCallback: ((attackType: string, originPos: Vector3, directionOrRadius: Vector3, windupSec: number) -> ())? = nil

function BossManager.setDamageCallback(cb: (target: Player, damage: number, source: Vector3) -> ())
	damageCallback = cb
end

function BossManager.setTelegraphCallback(cb: (attackType: string, originPos: Vector3, directionOrRadius: Vector3, windupSec: number) -> ())
	telegraphCallback = cb
end

-- Attack tunables. Two attacks alternate via random selection; each
-- has its own windup window (peer audit: 1.8s for Slam, 1.5s for Beam
-- — kids on Xbox controllers need 1.5-2s to react). Range/damage from
-- the EnemyConfig.Blaze entry where applicable; Slam radius and Beam
-- length live here because they're attack-specific, not boss-specific.
local SLAM_RADIUS = 30 -- studs
local SLAM_DAMAGE = 35
local SLAM_WINDUP = 1.8

local BEAM_LENGTH = 80
local BEAM_HITBOX_WIDTH = 3 -- tighter than the visual telegraph (4) so dodging feels fair
local BEAM_DAMAGE = 30
local BEAM_WINDUP = 1.5

local ATTACK_INTERVAL = 5 -- seconds between attack starts

-- Find a random alive player who is in the Arena (not in the Lair) to
-- target. Returns nil if no valid targets — boss idles for the next
-- attack interval rather than firing into empty space.
local function pickRandomArenaTarget(): Player?
	local candidates: { Player } = {}
	-- ZoneManager check kept loose: we don't require the local
	-- BossManager to know about ZoneManager; init.server.luau's
	-- damageCallback (npcDamagePlayer) already filters out Lair players
	-- via the existing Sprint 5 Part D path. Candidates here are just
	-- alive players with a character.
	for _, p in Players:GetPlayers() do
		if p.Character and p.Character.PrimaryPart then
			local hum = p.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				table.insert(candidates, p)
			end
		end
	end
	if #candidates == 0 then return nil end
	return candidates[math.random(1, #candidates)]
end

-- Inferno Slam attack execution. Picks a target's current position,
-- fires the telegraph, waits the windup, then applies damage to anyone
-- in the slam radius of the locked-in position. Doesn't track the
-- target after the telegraph fires — kids dodge by leaving the circle.
local function executeInfernoSlam(state: BossState)
	local target = pickRandomArenaTarget()
	if not target or not target.Character or not target.Character.PrimaryPart then return end
	local lockedPos = target.Character.PrimaryPart.Position

	if telegraphCallback then
		-- Pack radius into directionOrRadius.X per the BossTelegraph
		-- remote contract (commit 2).
		telegraphCallback("InfernoSlam", lockedPos, Vector3.new(SLAM_RADIUS, 0, 0), SLAM_WINDUP)
	end
	task.wait(SLAM_WINDUP)
	if not state.alive then return end -- boss died mid-windup, abort

	-- Apply damage to anyone within SLAM_RADIUS of the locked position.
	-- The "locked-in" semantics are intentional — kids must MOVE to
	-- dodge, not just be elsewhere when the timer ends.
	for _, p in Players:GetPlayers() do
		if p.Character and p.Character.PrimaryPart then
			local dist = (p.Character.PrimaryPart.Position - lockedPos).Magnitude
			if dist <= SLAM_RADIUS and damageCallback then
				damageCallback(p, SLAM_DAMAGE, state.rootPart.Position)
			end
		end
	end
end

-- Magma Beam attack execution. Fires from boss → target's current
-- position. Direction is locked at telegraph time; kids dodge sideways.
-- Hitbox is a thin rectangular volume of length BEAM_LENGTH from boss
-- along the direction unit vector.
local function executeMagmaBeam(state: BossState)
	local target = pickRandomArenaTarget()
	if not target or not target.Character or not target.Character.PrimaryPart then return end
	local bossPos = state.rootPart.Position
	local targetPos = target.Character.PrimaryPart.Position
	local toTarget = targetPos - bossPos
	if toTarget.Magnitude < 0.1 then return end
	local direction = toTarget.Unit

	if telegraphCallback then
		telegraphCallback("MagmaBeam", bossPos, direction, BEAM_WINDUP)
	end
	task.wait(BEAM_WINDUP)
	if not state.alive then return end

	-- Hitbox: anyone whose projection onto the beam axis is in
	-- [0, BEAM_LENGTH] AND whose perpendicular distance from the axis
	-- is within BEAM_HITBOX_WIDTH. Standard "point in oriented box"
	-- decomposition into axis-aligned tests via dot product.
	for _, p in Players:GetPlayers() do
		if p.Character and p.Character.PrimaryPart then
			local toPlayer = p.Character.PrimaryPart.Position - bossPos
			local distAlongBeam = toPlayer:Dot(direction)
			if distAlongBeam > 0 and distAlongBeam < BEAM_LENGTH then
				local perpVec = toPlayer - direction * distAlongBeam
				if perpVec.Magnitude < BEAM_HITBOX_WIDTH and damageCallback then
					damageCallback(p, BEAM_DAMAGE, bossPos)
				end
			end
		end
	end
end

-- AI tick. Runs as a coroutine started from spawnBlaze. Loops while
-- the boss is alive AND is the currently-active boss (the activeBoss
-- == state guard catches the rare race where despawn() ran but the
-- coroutine hasn't seen it yet). Picks a random attack each interval.
local function runBossAITick(state: BossState)
	-- Brief pause before first attack so kids have time to react to
	-- the boss appearing before getting blasted. Same purpose as the
	-- 3-second wave-INCOMING window in the standard wave loop.
	task.wait(3)
	while activeBoss == state and state.alive do
		local attack = if math.random() < 0.5 then "Slam" else "Beam"
		if attack == "Slam" then
			executeInfernoSlam(state)
		else
			executeMagmaBeam(state)
		end
		task.wait(ATTACK_INTERVAL)
	end
end

-- Hook spawnBlaze to start the AI tick. We do this by wrapping the
-- existing function rather than mutating its body — keeps the spawn
-- bookkeeping in one place and the AI in another.
local originalSpawnBlaze = BossManager.spawnBlaze
function BossManager.spawnBlaze(playerCount: number): BossState?
	local state = originalSpawnBlaze(playerCount)
	if state then
		task.spawn(runBossAITick, state)
	end
	return state
end

return BossManager
