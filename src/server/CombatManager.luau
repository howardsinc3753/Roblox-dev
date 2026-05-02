--!strict
-- Handles all combat logic server-side.
-- Validates attacks, applies damage, tracks KOs.

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
}

local playerStates: { [number]: CombatState } = {}
local BREATH_COOLDOWN = 1.0
local SPECIAL_COOLDOWN = 10.0
local BREATH_RANGE = 100 -- studs
local BREATH_SPEED = 150 -- studs/sec

function CombatManager.initPlayer(player: Player, dragonId: string)
	local dragon = DragonConfig[dragonId]
	if not dragon then
		dragonId = "Ember"
		dragon = DragonConfig.Ember
	end

	playerStates[player.UserId] = {
		dragonId = dragonId,
		health = dragon.health,
		maxHealth = dragon.health,
		alive = true,
		lastBreathTime = 0,
		lastSpecialTime = 0,
	}
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

	if state.health <= 0 then
		state.alive = false
		return true, damage
	end

	return false, damage
end

function CombatManager.respawn(player: Player)
	local state = playerStates[player.UserId]
	if state then
		local dragon = DragonConfig[state.dragonId]
		if dragon then
			state.health = dragon.health
			state.maxHealth = dragon.health
			state.alive = true
		end
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

-- Raycast-style hit detection for breath attacks
function CombatManager.findHitPlayer(shooter: Player, origin: Vector3, direction: Vector3): Player?
	local shooterState = playerStates[shooter.UserId]
	if not shooterState then
		return nil
	end

	local ray = Ray.new(origin, direction.Unit * BREATH_RANGE)
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
						-- Simple sphere check: is the player within range and roughly in the direction?
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

return CombatManager
