--!strict
-- Handles all combat logic server-side.
-- Validates attacks, applies damage, tracks KOs, syncs health to Humanoid.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DragonConfig = require(ReplicatedStorage.Shared.Modules:WaitForChild("DragonConfig"))

local CombatManager = {}

-- Runtime state per player
export type CombatState = {
	dragonId: string,
	health: number,
	maxHealth: number,
	alive: boolean,
	lastBreathTime: number,
	lastSpecialTime: number,
	lastDamageTime: number, -- updated on damage taken OR dealt; gates HP regen
}

local playerStates: { [number]: CombatState } = {}
local BREATH_COOLDOWN = 0.5
local SPECIAL_COOLDOWN = 10.0
local BREATH_RANGE = 100 -- studs

-- HP regen out of combat. Discourages kamikaze respawn loops and gives
-- defensive players a reason to disengage and reposition instead of
-- always charging in.
local REGEN_DELAY = 3.0 -- seconds of no combat activity before regen starts
local REGEN_RATE = 5 -- HP per second when regen is active
local REGEN_TICK = 1.0 -- how often the regen loop applies a tick

-- Sync CombatState health to the Humanoid on the character model
local function syncHealthToHumanoid(player: Player, state: CombatState)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.MaxHealth = state.maxHealth
	humanoid.Health = state.health
end

function CombatManager.initPlayer(player: Player, dragonId: string)
	local dragon = DragonConfig[dragonId]
	if not dragon then
		dragonId = "Ember"
		dragon = DragonConfig.Ember
	end

	local state: CombatState = {
		dragonId = dragonId,
		health = dragon.health,
		maxHealth = dragon.health,
		alive = true,
		lastBreathTime = 0,
		lastSpecialTime = 0,
		lastDamageTime = 0,
	}
	playerStates[player.UserId] = state
	syncHealthToHumanoid(player, state)
end

function CombatManager.getState(player: Player): CombatState?
	return playerStates[player.UserId]
end

function CombatManager.removePlayer(player: Player)
	playerStates[player.UserId] = nil
end

function CombatManager.canFireBreath(player: Player): boolean
	local state = playerStates[player.UserId]
	if not state or not state.alive then
		return false
	end
	return (tick() - state.lastBreathTime) >= BREATH_COOLDOWN
end

function CombatManager.canUseSpecial(player: Player): boolean
	local state = playerStates[player.UserId]
	if not state or not state.alive then
		return false
	end
	return (tick() - state.lastSpecialTime) >= SPECIAL_COOLDOWN
end

function CombatManager.recordBreath(player: Player)
	local state = playerStates[player.UserId]
	if state then
		state.lastBreathTime = tick()
	end
end

function CombatManager.recordSpecial(player: Player)
	local state = playerStates[player.UserId]
	if state then
		state.lastSpecialTime = tick()
	end
end

-- Apply damage to a target. Returns (killed: boolean, actualDamage: number)
function CombatManager.applyDamage(target: Player, damage: number): (boolean, number)
	local state = playerStates[target.UserId]
	if not state or not state.alive then
		return false, 0
	end

	state.health = math.max(0, state.health - damage)
	state.lastDamageTime = tick() -- victim is "in combat" — pauses their regen
	syncHealthToHumanoid(target, state)

	if state.health <= 0 then
		state.alive = false
		return true, damage
	end

	return false, damage
end

-- Mark a player as having dealt damage. Called from init.server.luau after a
-- successful hit so the attacker's HP regen also pauses (otherwise an aggressor
-- who lands hits but takes none could heal mid-fight).
function CombatManager.recordDamageDealt(player: Player)
	local state = playerStates[player.UserId]
	if state then
		state.lastDamageTime = tick()
	end
end

function CombatManager.respawn(player: Player)
	local state = playerStates[player.UserId]
	if state then
		local dragon = DragonConfig[state.dragonId]
		if dragon then
			state.health = dragon.health
			state.maxHealth = dragon.health
			state.alive = true
			state.lastDamageTime = 0 -- fresh respawn, regen ready immediately if hurt
			syncHealthToHumanoid(player, state)
		end
	end
end

-- Periodic HP regen. Players who haven't taken or dealt damage for REGEN_DELAY
-- seconds heal REGEN_RATE HP per second, capped at maxHealth.
function CombatManager.startRegenLoop()
	task.spawn(function()
		while true do
			task.wait(REGEN_TICK)
			local now = tick()
			for userId, state in playerStates do
				if state.alive and state.health < state.maxHealth then
					if (now - state.lastDamageTime) >= REGEN_DELAY then
						local heal = REGEN_RATE * REGEN_TICK
						state.health = math.min(state.maxHealth, state.health + heal)
						local player = Players:GetPlayerByUserId(userId)
						if player then
							syncHealthToHumanoid(player, state)
						end
					end
				end
			end
		end
	end)
end

function CombatManager.healPlayer(player: Player, amount: number)
	local state = playerStates[player.UserId]
	if state and state.alive then
		state.health = math.min(state.health + amount, state.maxHealth)
		syncHealthToHumanoid(player, state)
	end
end

function CombatManager.addArmor(player: Player, bonusHp: number)
	local state = playerStates[player.UserId]
	if state and state.alive then
		state.maxHealth += bonusHp
		state.health += bonusHp
		syncHealthToHumanoid(player, state)
	end
end

function CombatManager.isAlive(player: Player): boolean
	local state = playerStates[player.UserId]
	return state ~= nil and state.alive
end

function CombatManager.getHealth(player: Player): (number, number)
	local state = playerStates[player.UserId]
	if state then
		return state.health, state.maxHealth
	end
	return 0, 0
end

-- Cone-based hit detection for breath attacks
function CombatManager.findHitPlayer(shooter: Player, origin: Vector3, direction: Vector3): Player?
	local shooterState = playerStates[shooter.UserId]
	if not shooterState then
		return nil
	end

	local closestPlayer: Player? = nil
	local closestDist = BREATH_RANGE

	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= shooter then
			local otherState = playerStates[otherPlayer.UserId]
			if otherState and otherState.alive then
				local character = otherPlayer.Character
				if character then
					local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if rootPart then
						local toTarget = rootPart.Position - origin
						local dist = toTarget.Magnitude
						if dist < closestDist then
							local dot = toTarget.Unit:Dot(direction.Unit)
							if dot > 0.85 then -- ~30 degree cone
								closestDist = dist
								closestPlayer = otherPlayer
							end
						end
					end
				end
			end
		end
	end

	return closestPlayer
end

-- Same cone hit detection but checks a list of NPC states (NPCManager.getAlive()).
-- Returns the closest NPC model or nil. Kept separate from findHitPlayer because
-- NPCs aren't Player objects — different state structure, different reward path.
function CombatManager.findHitNPC(npcStates: { any }, origin: Vector3, direction: Vector3): any?
	local closest: any = nil
	local closestDist = BREATH_RANGE

	for _, npc in npcStates do
		if npc.alive and npc.rootPart then
			local toTarget = npc.rootPart.Position - origin
			local dist = toTarget.Magnitude
			if dist < closestDist then
				local dot = toTarget.Unit:Dot(direction.Unit)
				if dot > 0.85 then
					closestDist = dist
					closest = npc
				end
			end
		end
	end
	return closest
end

-- Cone hit detection for forward-vortex specials. Like findHitPlayer but
-- returns ALL players in the cone (not just the closest). dotThreshold of
-- 0.7 = ~45 degree half-angle = 90 degree full cone — wide enough to feel
-- like a sweeping vortex, narrow enough that you have to actually face the
-- enemy.
function CombatManager.findPlayersInCone(origin: Vector3, direction: Vector3, range: number, dotThreshold: number, exclude: Player?): { Player }
	local result: { Player } = {}
	if direction.Magnitude < 0.001 then return result end
	local dirUnit = direction.Unit
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= exclude then
			local otherState = playerStates[otherPlayer.UserId]
			if otherState and otherState.alive then
				local character = otherPlayer.Character
				if character and character.PrimaryPart then
					local toTarget = character.PrimaryPart.Position - origin
					local dist = toTarget.Magnitude
					if dist > 0 and dist <= range then
						local dot = toTarget.Unit:Dot(dirUnit)
						if dot >= dotThreshold then
							table.insert(result, otherPlayer)
						end
					end
				end
			end
		end
	end
	return result
end

-- Same cone test but for NPCs. Lets specials sweep through PvE waves too.
function CombatManager.findNPCsInCone(npcStates: { any }, origin: Vector3, direction: Vector3, range: number, dotThreshold: number): { any }
	local result: { any } = {}
	if direction.Magnitude < 0.001 then return result end
	local dirUnit = direction.Unit
	for _, npc in npcStates do
		if npc.alive and npc.rootPart then
			local toTarget = npc.rootPart.Position - origin
			local dist = toTarget.Magnitude
			if dist > 0 and dist <= range then
				local dot = toTarget.Unit:Dot(dirUnit)
				if dot >= dotThreshold then
					table.insert(result, npc)
				end
			end
		end
	end
	return result
end

-- Find all players within radius of a position
function CombatManager.findPlayersInRadius(center: Vector3, radius: number, exclude: Player?): { Player }
	local result: { Player } = {}
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= exclude then
			local otherState = playerStates[otherPlayer.UserId]
			if otherState and otherState.alive then
				local character = otherPlayer.Character
				if character and character.PrimaryPart then
					local dist = (character.PrimaryPart.Position - center).Magnitude
					if dist <= radius then
						table.insert(result, otherPlayer)
					end
				end
			end
		end
	end
	return result
end

return CombatManager
