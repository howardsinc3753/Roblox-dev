--!strict
-- Dragon Warz — Client Entry Point
-- Wires up flight, camera, combat, HUD, sounds, and special effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Wait for remotes to be created by server
local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not remotes then
	warn("[Client] Timed out waiting for Remotes folder")
	return
end

-- Load client modules
local FlightController = require(script.FlightController)
local CameraController = require(script.CameraController)
local CombatInput = require(script.CombatInput)
local HUD = require(script.HUD)
local SoundManager = require(script.SoundManager)
local DragonSelectUI = require(script.DragonSelectUI)
local RoundEndSummary = require(script.RoundEndSummary)
local LockOnController = require(script.LockOnController)
local Awareness = require(script.Awareness)
local WelcomeBanner = require(script.WelcomeBanner)
local MobileControls = require(script.MobileControls)
local ControlsOverlay = require(script.ControlsOverlay)
local TipManager = require(script.TipManager)
local SafeZoneIndicator = require(script.SafeZoneIndicator)
local WaveTracker = require(script.WaveTracker)
local DragonUpgradeUI = require(script.DragonUpgradeUI)
local LairAtmosphere = require(script.LairAtmosphere)
local BossTelegraph = require(script.BossTelegraph)

print(`[Client] {player.Name} Dragon Warz client starting...`)

-- Initialize systems
CombatInput.init()
HUD.create()
SoundManager.init()
SoundManager.startMusic()
DragonSelectUI.init()
DragonSelectUI.create()
RoundEndSummary.create()
LockOnController.init()
Awareness.create()
WelcomeBanner.create()
-- Touch UI for mobile (iPad/iPhone/Android). No-op on keyboard devices.
MobileControls.init()
-- Sprint 5 Part C/D: "🏠 SAFE ZONE" pill while Player.Zone == Lair.
-- Reads ZoneManager's per-player attribute; no remote subscription needed.
SafeZoneIndicator.init()
-- Sprint 6: wave-state HUD (incoming banner / counter / countdown).
-- Self-contained ScreenGui so a syntax error here can't take HUD down.
WaveTracker.init()
-- Sprint 7: stat-upgrade modal. Built once (.create), opened on demand
-- (.open) from the Stat Stone's ProximityPrompt handler below.
DragonUpgradeUI.create()
DragonUpgradeUI.init()
-- Sprint 8: per-zone Lighting tint. Reads Player.Zone attribute (Sprint 5
-- ZoneManager) and shifts global Lighting toward magical-realm purple-gold
-- when in the Lair, restores Studio baseline when in the Arena.
LairAtmosphere.init()
-- Sprint 10: render Mega Boss attack telegraphs (red circle / line
-- preview) when the server fires the BossTelegraph remote. Subscribes
-- to the remote internally; spawning the renderer Parts happens on
-- demand from the OnClientEvent handler.
BossTelegraph.init()

-- Sprint 10: boss music swap. Server fires BossMusicState(true) when
-- Blaze appears, BossMusicState(false) on victory or timeout. The
-- SoundManager pitch-shifts the existing arena music instead of
-- swapping to a dedicated track (peer audit guidance — pitch-shift
-- of existing music carries enough signal for MVP).
do
	local bossMusicRemote = remotes:WaitForChild("BossMusicState", 10) :: RemoteEvent?
	if bossMusicRemote then
		bossMusicRemote.OnClientEvent:Connect(function(active: boolean)
			SoundManager.setBossMusicActive(active)
		end)
	end
end

-- Fetch initial player data so DragonSelectUI knows what's unlocked + selected.
-- The server creates the GetPlayerData RemoteFunction in NetworkSetup; it returns
-- the cached PlayerData table. Wrapped in pcall + retry because remotes may not
-- be ready at first script execution depending on join timing.
task.spawn(function()
	local getPlayerDataFunc = remotes:WaitForChild("GetPlayerData", 10) :: RemoteFunction?
	if not getPlayerDataFunc then return end
	-- Wait briefly so server's PlayerAdded handler has finished loadPlayer
	task.wait(1)
	local ok, data = pcall(function()
		return getPlayerDataFunc:InvokeServer()
	end)
	if ok and data then
		DragonSelectUI.updatePlayerData(data)
		-- Sprint 7: feed the upgrade modal too so it knows which dragons are
		-- unlocked, the kid's coin balance, current selection, upgrade levels,
		-- and tutorial-seen flag — without these, opening the modal renders
		-- empty stat rows for every dragon.
		DragonUpgradeUI.updatePlayerData(data)
		-- Retention: show welcome banner with daily login bonus + streak.
		-- Server populated welcomeBonus in DataManager.processLogin. Banner
		-- self-throttles to once-per-session via internal flag.
		if data.welcomeBonus then
			WelcomeBanner.show(data.welcomeBonus)
		end
		-- HUD streak indicator updates every time data refreshes (cheap).
		HUD.setStreak(data.loginStreak or 0)
	else
		-- Single-shot fetch: if it fails, the welcome banner + streak badge
		-- silently never render this session even though the server already
		-- granted the daily bonus coins. Surface the failure so it's
		-- debuggable rather than invisible — the most common cause is
		-- server-side script error before GetPlayerData was registered.
		-- (Future: add a bounded retry loop here if this becomes a real
		-- player-facing issue.)
		warn(`[Client] GetPlayerData failed; welcome banner + streak badge will not render this session. Error: {tostring(data)}`)
	end
end)

-- Current state
local currentDragonId = "Ember"
local INTERMISSION_DURATION = 15

-- ================================
-- REMOTE EVENT HANDLERS
-- ================================

local spawnDragonRemote = remotes:WaitForChild("SpawnDragon") :: RemoteEvent
local updateCoinsRemote = remotes:WaitForChild("UpdateCoins") :: RemoteEvent
local damagePlayerRemote = remotes:WaitForChild("DamagePlayer") :: RemoteEvent
local playerKORemote = remotes:WaitForChild("PlayerKO") :: RemoteEvent
local roundStartRemote = remotes:WaitForChild("RoundStart") :: RemoteEvent
local roundEndRemote = remotes:WaitForChild("RoundEnd") :: RemoteEvent
local updateScoreboardRemote = remotes:WaitForChild("UpdateScoreboard") :: RemoteEvent
local syncTimerRemote = remotes:WaitForChild("SyncTimer") :: RemoteEvent
local specialEffectRemote = remotes:WaitForChild("SpecialEffect") :: RemoteEvent
local damageNPCRemote = remotes:WaitForChild("DamageNPC") :: RemoteEvent
local npcBreathFiredRemote = remotes:WaitForChild("NPCBreathFired") :: RemoteEvent
local lockedByEnemyRemote = remotes:WaitForChild("LockedByEnemy") :: RemoteEvent
local shieldActivatedRemote = remotes:WaitForChild("ShieldActivated") :: RemoteEvent

-- Dragon spawned/changed
spawnDragonRemote.OnClientEvent:Connect(function(dragonId: string)
	currentDragonId = dragonId
	FlightController.setDragon(dragonId)
	CombatInput.setDragon(dragonId)
	HUD.setDragon(dragonId)
	-- Sprint 7: tell the upgrade modal which dragon the kid is currently
	-- flying so opening the modal defaults to "their" dragon's tab.
	DragonUpgradeUI.setSelectedDragon(dragonId)

	task.defer(function()
		local character = player.Character or player.CharacterAdded:Wait()
		character:WaitForChild("HumanoidRootPart", 5)
		FlightController.enable()
		CameraController.enable()
		CombatInput.enable()
		-- FTUE: progressive tutorial pills (one prompt at a time, dismissed
		-- by doing the action). Replaces the all-at-once ControlsOverlay
		-- which kid playtest showed was overwhelming + instantly forgotten.
		-- Self-throttles to once per session.
		TipManager.startSequence()
		-- Big controls card is still available — for now we don't auto-show
		-- it. Future: bind to a "Help" button in the dragon-select menu so
		-- curious kids can pull up the full reference.
		-- ControlsOverlay.show() — disabled per playtest feedback
		_ = ControlsOverlay -- silence unused-import warning until we wire the menu help button
	end)
end)

-- Coins updated
updateCoinsRemote.OnClientEvent:Connect(function(coins: number)
	HUD.updateCoins(coins)
	DragonSelectUI.updateCoins(coins)
	-- Sprint 7: keep the upgrade modal's cached coin count fresh so the
	-- "+ N 🪙" buttons recompute affordability immediately on every coin
	-- change (kill reward, wave-clear bonus, post-round payout).
	DragonUpgradeUI.updateCoins(coins)
	SoundManager.play("Coin")
end)

-- Sprint 7: server pushes upgraded stats for a specific dragon. Drives:
--   - DragonUpgradeUI panel (rerender stat rows with new level + cost)
--   - HUD "Lv N" badge (only if the upgraded dragon is the one the player
--     is currently flying — tracked via currentDragonId on the client)
--   - FlightController speed cache (so +Spd upgrades take effect on
--     movement immediately, not only after dragon switch / respawn)
do
	local statsRemote = remotes:WaitForChild("DragonStatsUpdated", 10) :: RemoteEvent?
	if statsRemote then
		statsRemote.OnClientEvent:Connect(function(dragonId: string, levels: any, effective: any)
			DragonUpgradeUI.updateStats(dragonId, levels, effective)
			-- Sprint 7 polish: keep the B-menu's per-card Lv N badge in
			-- sync as upgrades land. Without this, the badge only refreshes
			-- on the next GetPlayerData round-trip (only happens at join).
			DragonSelectUI.updateDragonLevels(dragonId, levels)
			-- Apply speed override to the flight controller so a +Spd
			-- upgrade visibly affects movement without a respawn (peer #6).
			if effective and effective.speed then
				FlightController.applyEffectiveSpeed(dragonId, effective.speed)
			end
			-- Update the HUD "Lv N" badge ONLY when the upgraded dragon is
			-- the one the kid is flying. currentDragonId is updated by the
			-- existing SpawnDragon handler, so this comparison is correct
			-- as long as those events arrive in order — which they do
			-- (server fires SpawnDragon before DragonStatsUpdated in
			-- processPlayer + selectDragon paths).
			if effective and effective.totalLevel and dragonId == currentDragonId then
				HUD.setDragonLevel(effective.totalLevel)
			end
		end)
	end
end

-- Reusable floating damage number — used for both player hits and NPC hits.
-- Adornee accepts any BasePart so we can show numbers above NPC root parts too.
local function showFloatingDamage(adornee: BasePart, damage: number)
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Size = UDim2.fromOffset(100, 40)
	billboardGui.StudsOffset = Vector3.new(math.random(-2, 2), 6, 0)
	billboardGui.Adornee = adornee
	billboardGui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = `-{damage}`
	label.TextColor3 = Color3.fromRGB(255, 50, 50)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboardGui

	task.spawn(function()
		for i = 1, 20 do
			task.wait(0.05)
			billboardGui.StudsOffset += Vector3.new(0, 0.2, 0)
			label.TextTransparency = i / 20
			label.TextStrokeTransparency = i / 20
		end
		billboardGui:Destroy()
	end)
end

-- Damage dealt to a player (PvP or NPC→player). Server now passes a 3rd arg
-- `sourcePosition` so the victim's client can render a damage-direction arc.
damagePlayerRemote.OnClientEvent:Connect(function(targetUserId: number, damage: number, sourcePosition: Vector3?)
	SoundManager.play("Hit")

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if targetPlayer and targetPlayer.Character then
		local rootPart = targetPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			showFloatingDamage(rootPart, damage)
		end
	end

	-- Damage-direction indicator: only show for the LOCAL player taking damage
	-- (showing arrows for someone else's damage would just be screen clutter).
	if targetUserId == player.UserId and sourcePosition then
		Awareness.showDamageFrom(sourcePosition)
	end

	-- Teach the kid about the shield button on FIRST damage taken. HUD
	-- self-throttles to once per session; safe to call on every damage event.
	-- The arrow + "Press R for Shield!" balloon points at the shield panel.
	if targetUserId == player.UserId then
		HUD.showShieldHint()
	end
end)

-- H1+H3 fix: damage dealt to an NPC. Server fires this to the SHOOTER ONLY
-- (so others' combat doesn't spam our hit sound). We render a floating "-X"
-- above the NPC's root part.
damageNPCRemote.OnClientEvent:Connect(function(npcModel: Model, damage: number)
	if not npcModel or not npcModel.PrimaryPart then return end
	SoundManager.play("Hit")
	showFloatingDamage(npcModel.PrimaryPart, damage)
end)

-- Sprint 7: practice-dummy hit feedback. Server fires this to the shooter
-- when their breath cone hits a tagged Lair dummy. Renders the same
-- floating "-N" pattern as NPC hits + plays the Hit sound. Server is
-- authoritative on the damage number; client just visualizes.
do
	local dummyHitRemote = remotes:WaitForChild("DummyHit", 10) :: RemoteEvent?
	if dummyHitRemote then
		dummyHitRemote.OnClientEvent:Connect(function(dummyPart: BasePart, damage: number, _newHp: number, _maxHp: number)
			if not dummyPart or not dummyPart.Parent then return end
			SoundManager.play("Hit")
			showFloatingDamage(dummyPart, damage)
		end)
	end
end

-- H2 fix: render a visible projectile from an attacking NPC to its target.
-- Fired to all clients so everyone sees the breath, not just the victim.
npcBreathFiredRemote.OnClientEvent:Connect(function(npcModel: Model, targetPos: Vector3, color: Color3)
	if not npcModel or not npcModel.PrimaryPart then return end
	local origin = npcModel.PrimaryPart.Position
	local direction = (targetPos - origin)
	if direction.Magnitude < 0.1 then return end
	direction = direction.Unit

	-- Projectile: same general look as player breath but tinted to the NPC color
	local projectile = Instance.new("Part")
	projectile.Name = "NPCBreath"
	projectile.Size = Vector3.new(2, 2, 4)
	projectile.Shape = Enum.PartType.Ball
	projectile.Color = color
	projectile.Material = Enum.Material.Neon
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CFrame = CFrame.lookAt(origin, origin + direction)
	projectile.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = projectile
	local attachment2 = Instance.new("Attachment")
	attachment2.Position = Vector3.new(0, 0, 1)
	attachment2.Parent = projectile
	local trail = Instance.new("Trail")
	trail.Color = ColorSequence.new(color)
	trail.Lifetime = 0.3
	trail.MinLength = 0.1
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.Attachment0 = attachment
	trail.Attachment1 = attachment2
	trail.Parent = projectile

	local distance = (targetPos - origin).Magnitude
	local speed = 150
	local duration = math.min(distance / speed, 1.0) -- cap so very long shots don't linger
	local endPos = origin + direction * distance

	local TweenService = game:GetService("TweenService")
	local tween = TweenService:Create(projectile, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(endPos, endPos + direction),
	})
	tween:Play()
	tween.Completed:Connect(function()
		projectile:Destroy()
	end)
end)

-- Lock-on warning: another player has locked onto YOU. Brief red border
-- pulse + tick sound so you know to break LOS or dodge before they fire.
-- Doesn't pause the game or block anything — purely informational.
do
	local playerGuiRef = player:WaitForChild("PlayerGui") :: PlayerGui
	local warningGui: ScreenGui? = nil
	local warningCoroutine: thread? = nil

	local function ensureWarningGui()
		if warningGui then return end
		warningGui = Instance.new("ScreenGui")
		warningGui.Name = "LockWarning"
		warningGui.ResetOnSpawn = false
		warningGui.IgnoreGuiInset = true
		warningGui.DisplayOrder = 8 -- above HUD/compass, below modal UIs
		warningGui.Enabled = false
		warningGui.Parent = playerGuiRef

		-- Four red strips around the screen edge form a "border pulse".
		-- Cheap (4 frames) and reads instantly as "warning state".
		local function makeStrip(name: string, sizeUDim: UDim2, posUDim: UDim2)
			local strip = Instance.new("Frame")
			strip.Name = name
			strip.Size = sizeUDim
			strip.Position = posUDim
			strip.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
			strip.BackgroundTransparency = 0.2
			strip.BorderSizePixel = 0
			strip.Parent = warningGui
		end
		makeStrip("Top", UDim2.new(1, 0, 0, 8), UDim2.fromScale(0, 0))
		makeStrip("Bottom", UDim2.new(1, 0, 0, 8), UDim2.new(0, 0, 1, -8))
		makeStrip("Left", UDim2.new(0, 8, 1, 0), UDim2.fromScale(0, 0))
		makeStrip("Right", UDim2.new(0, 8, 1, 0), UDim2.new(1, -8, 0, 0))

		local label = Instance.new("TextLabel")
		label.Name = "LockedText"
		label.Size = UDim2.fromOffset(280, 36)
		label.Position = UDim2.new(0.5, -140, 0.85, 0)
		label.BackgroundTransparency = 1
		label.Text = "LOCKED"
		label.TextColor3 = Color3.fromRGB(255, 60, 60)
		label.TextStrokeTransparency = 0
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.Parent = warningGui
	end

	lockedByEnemyRemote.OnClientEvent:Connect(function(_attackerUserId: number, _attackerName: string?)
		ensureWarningGui()
		if not warningGui then return end

		-- Pulse the warning briefly. Cancel any existing pulse first so
		-- back-to-back lock pings don't stutter.
		if warningCoroutine then
			task.cancel(warningCoroutine)
			warningCoroutine = nil
		end
		SoundManager.play("Hit") -- repurpose Hit sound as a tick; cheap reuse

		warningCoroutine = task.spawn(function()
			warningGui.Enabled = true
			-- Two-pulse pattern: bright/dim/bright/dim/off. ~0.8s total.
			for _, t in { 0.15, 0.4, 0.15, 0.4 } do
				for _, child in warningGui:GetChildren() do
					if child:IsA("Frame") then
						(child :: Frame).BackgroundTransparency = t
					end
				end
				task.wait(0.1)
			end
			warningGui.Enabled = false
			warningCoroutine = nil
		end)
	end)
end

-- Player KO. Server fires this for player-vs-player AND for NPC kills:
--   killerUserId=0  → killed by NPC (enemyName carries the enemy type)
--   victimUserId=0  → player killed an NPC (enemyName carries the enemy type)
playerKORemote.OnClientEvent:Connect(function(killerUserId: number, victimUserId: number, enemyName: string?)
	local killerName: string
	local victimName: string

	if killerUserId == 0 then
		-- NPC killed a player
		killerName = enemyName or "Enemy"
	else
		local killer = Players:GetPlayerByUserId(killerUserId)
		killerName = if killer then killer.Name else "???"
	end

	if victimUserId == 0 then
		-- Player killed an NPC
		victimName = enemyName or "Enemy"
	else
		local victim = Players:GetPlayerByUserId(victimUserId)
		victimName = if victim then victim.Name else "???"
	end

	HUD.addKillFeed(killerName, victimName)
	SoundManager.play("KO")

	if victimUserId == player.UserId then
		HUD.updateRoundTimer("Eliminated! Respawning in 5s...")
		FlightController.disable()
		CombatInput.disable()
		-- Big death feedback: full-screen red overlay + "YOU DIED" banner +
		-- explosion sound + respawn countdown. Without this, kids couldn't
		-- tell whether they died or just lost camera control.
		HUD.showDeathOverlay(killerName, 5)
		SoundManager.play("KO") -- second hit on KO sound for emphasis on the local death

		task.delay(5, function()
			FlightController.enable()
			CombatInput.enable()
		end)
	end
end)

-- Round start: hide dragon select, return mouse to lock-center for combat.
-- Sprint 6: the HUD round-timer no longer ticks down — WaveTracker is the
-- canonical round-progress UI now (wave incoming/active/clear/resting).
-- We just show "Round N" so the HUD still reflects round state, without
-- presenting the safety-cap (240s) clock as if it were a meaningful timer.
roundStartRemote.OnClientEvent:Connect(function(roundNumber: number, _duration: number)
	HUD.updateRoundTimer(`Round {roundNumber}`)
	SoundManager.play("RoundStart")
	DragonSelectUI.hide()
	FlightController.enable()
	CameraController.enable()
	CombatInput.enable()
end)

-- Round end: show summary first, then dragon select for the rest of intermission.
-- Server now sends a third arg (coinsEarned per userId) for the personal payout.
-- 4th arg `firstWinClaimed` is { [userId]: true } for players who just claimed
-- their first-win-of-day bonus this round. Drives the gold "FIRST WIN TODAY"
-- highlight in the summary card.
-- 5th arg `waveResults` (Sprint 6): { { waveNum, status, clearTime, isBossWave } }
-- per-wave breakdown for the recap row. Optional — pre-Sprint-6 servers omit it.
roundEndRemote.OnClientEvent:Connect(function(winnerUserId: number, scoreboard: any, coinsEarned: any, firstWinClaimed: any, waveResults: any)
	local winner = Players:GetPlayerByUserId(winnerUserId)
	local winnerName = if winner then winner.Name else "No one"
	HUD.updateRoundTimer(`Round Over! Winner: {winnerName}`)
	SoundManager.play("RoundEnd")

	FlightController.disable()
	CombatInput.disable()

	-- Show summary first (auto-dismisses after ~6s), then open dragon select
	-- for the remaining intermission time.
	RoundEndSummary.show(winnerUserId, scoreboard, coinsEarned, firstWinClaimed, waveResults)
	task.delay(6, function()
		DragonSelectUI.show(9) -- ~9s left of the 15s intermission after summary
	end)
end)

-- Sprint 6: SyncTimer is now meaningless on the client — round duration
-- is wave-driven, not a fixed countdown. Kept the remote subscription as
-- a no-op stub so the server's existing periodic fire doesn't generate
-- "no listener" warnings; if SyncTimer is removed server-side later this
-- block can go too.
syncTimerRemote.OnClientEvent:Connect(function(_timeRemaining: number, _roundNumber: number)
	-- intentionally empty
end)

-- Special ability visual effects. 4th arg `direction` is the dragon's facing
-- direction at the moment of cast — Fire/Lightning use it to render a forward
-- vortex/cone instead of a self-centered burst.
-- Screen flash on local-player special cast. Brief white overlay fades out
-- in ~0.25s. Adds the "BIG MOMENT" feel kids expect for a panic-button. Only
-- triggers for the LOCAL player's casts (not other players') — otherwise
-- the screen would flash every time anyone casts anywhere on the map.
local function flashScreenWhite()
	local flashGui = player:FindFirstChild("PlayerGui"):FindFirstChild("CastFlash") :: ScreenGui?
	if not flashGui then
		flashGui = Instance.new("ScreenGui")
		flashGui.Name = "CastFlash"
		flashGui.ResetOnSpawn = false
		flashGui.IgnoreGuiInset = true
		flashGui.DisplayOrder = 20 -- above all gameplay UI for the brief flash
		flashGui.Enabled = false
		flashGui.Parent = player:FindFirstChild("PlayerGui")
		local flash = Instance.new("Frame")
		flash.Name = "Flash"
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		flash.BorderSizePixel = 0
		flash.BackgroundTransparency = 0
		flash.Parent = flashGui
	end
	local flash = flashGui:FindFirstChild("Flash") :: Frame
	flash.BackgroundTransparency = 0.4
	flashGui.Enabled = true
	task.spawn(function()
		for i = 1, 8 do
			task.wait(0.03)
			flash.BackgroundTransparency = 0.4 + (i / 8) * 0.6
		end
		flashGui.Enabled = false
	end)
end

-- Shield bubble visual: a 4-second translucent ForceField sphere around the
-- shielded dragon. Server fires this for everyone (so spectators see it too)
-- with the shielded player's userId.
shieldActivatedRemote.OnClientEvent:Connect(function(userId: number)
	local target = Players:GetPlayerByUserId(userId)
	if not target or not target.Character or not target.Character.PrimaryPart then return end
	local rootPart = target.Character.PrimaryPart

	-- Bubble sphere parented to the dragon model so it follows automatically.
	local bubble = Instance.new("Part")
	bubble.Name = "ShieldBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.new(20, 20, 20)
	bubble.Color = Color3.fromRGB(120, 200, 255)
	bubble.Material = Enum.Material.ForceField -- looks shieldy out of the box
	bubble.Anchored = false
	bubble.CanCollide = false
	bubble.Massless = true
	bubble.Transparency = 0.3
	bubble.CFrame = rootPart.CFrame
	bubble.Parent = target.Character

	-- Weld so the bubble follows the dragon without physics interactions.
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = bubble
	weld.Parent = bubble

	-- Auto-clean after the shield duration. Match the server's SHIELD_DURATION
	-- (4 seconds) — if these drift, the visual would mislead the kid.
	task.delay(4.0, function()
		if bubble and bubble.Parent then
			bubble:Destroy()
		end
	end)

	-- Distinct "shield up" sound so the kid hears confirmation independent
	-- of the visual (helpful when shielding while looking elsewhere).
	SoundManager.play("Special") -- reuse existing audio; adequate placeholder
end)

specialEffectRemote.OnClientEvent:Connect(function(userId: number, element: string, position: Vector3, direction: Vector3?)
	-- Element-specific layered SFX so each special reads distinctly. Fire is
	-- a deep whoosh+roar, Ice is crystalline shimmer, Lightning crackles, etc.
	SoundManager.playSpecialForElement(element)
	-- Drama: flash the screen on local player casts. Don't flash for
	-- other players' casts (that'd be visual spam in PvP chaos).
	if userId == player.UserId then
		flashScreenWhite()
	end
	local targetPlayer = Players:GetPlayerByUserId(userId)
	if not targetPlayer or not targetPlayer.Character then return end
	local rootPart = targetPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	-- Fallback: if server didn't pass direction (older protocol), aim cones forward
	-- in world space. Better than crashing.
	local forward = direction or Vector3.new(0, 0, -1)
	if forward.Magnitude < 0.001 then forward = Vector3.new(0, 0, -1) end
	forward = forward.Unit

	if element == "Fire" then
		-- Fire Vortex: an elongated cone of flame extending ~50 studs forward
		-- from the dragon. Uses a Cylinder pointed along `forward`, expanding
		-- in radius over 0.6s, plus a fast ParticleEmitter spitting embers.
		local vortex = Instance.new("Part")
		vortex.Shape = Enum.PartType.Cylinder
		vortex.Material = Enum.Material.Neon
		vortex.Color = Color3.fromRGB(255, 100, 30)
		vortex.Anchored = true
		vortex.CanCollide = false
		vortex.Transparency = 0.25
		vortex.Massless = true
		-- Cylinder's "length" axis is X. Rotate so X aligns with `forward`,
		-- then offset center to be 30 studs ahead of dragon (so it doesn't
		-- start inside the player).
		local startCenter = position + forward * 30
		vortex.CFrame = CFrame.lookAt(startCenter, startCenter + forward) * CFrame.Angles(0, math.rad(90), 0)
		vortex.Size = Vector3.new(60, 4, 4) -- length 60 (along X), radius starts small
		vortex.Parent = workspace

		-- Light source so the vortex actually illuminates terrain
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 140, 30)
		light.Brightness = 4
		light.Range = 40
		light.Parent = vortex

		-- Ember particles streaming forward
		local attach = Instance.new("Attachment")
		attach.Parent = vortex
		local particles = Instance.new("ParticleEmitter")
		particles.Texture = "rbxasset://textures/particles/fire_main.dds"
		particles.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 80)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 0)),
		})
		particles.Size = NumberSequence.new(3, 0.5)
		particles.Transparency = NumberSequence.new(0.2, 1)
		particles.Lifetime = NumberRange.new(0.4, 0.8)
		particles.Rate = 200
		particles.Speed = NumberRange.new(40, 70)
		particles.SpreadAngle = Vector2.new(20, 20)
		particles.Parent = attach

		-- Animate: short burst (~0.3s) so the player can't outrun the visual
		-- by boosting forward immediately after cast. The cone is anchored at
		-- the cast position; if it lingered, you'd see it floating behind you.
		task.spawn(function()
			for i = 1, 10 do
				task.wait(0.03)
				local r = 4 + i * 1.4 -- grows from 4 to 18 studs radius
				local t = 0.25 + (i / 10) * 0.7
				vortex.Size = Vector3.new(60, r, r)
				vortex.Transparency = t
				light.Brightness = 4 * (1 - i / 10)
			end
			particles.Enabled = false
			task.wait(0.2) -- short trailing-particle fade
			vortex:Destroy()
		end)

	elseif element == "Ice" then
		-- Ice wall: blue shield sphere
		local shield = Instance.new("Part")
		shield.Shape = Enum.PartType.Ball
		shield.Size = Vector3.new(15, 15, 15)
		shield.Position = position
		shield.Color = Color3.fromRGB(100, 180, 255)
		shield.Material = Enum.Material.ForceField
		shield.Anchored = true
		shield.CanCollide = false
		shield.Transparency = 0.5
		shield.Parent = game.Workspace

		task.delay(2, function() shield:Destroy() end)

	elseif element == "Lightning" then
		-- Lightning Cone: forward beam of crackling yellow energy. Same
		-- elongated-cylinder pattern as Fire but tighter, brighter, with
		-- alternating bright/dim flash cycles to read as electric.
		local beam = Instance.new("Part")
		beam.Shape = Enum.PartType.Cylinder
		beam.Material = Enum.Material.Neon
		beam.Color = Color3.fromRGB(255, 255, 80)
		beam.Anchored = true
		beam.CanCollide = false
		beam.Transparency = 0.2
		beam.Massless = true
		local startCenter = position + forward * 35
		beam.CFrame = CFrame.lookAt(startCenter, startCenter + forward) * CFrame.Angles(0, math.rad(90), 0)
		beam.Size = Vector3.new(70, 3, 3)
		beam.Parent = workspace

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(220, 220, 255)
		light.Brightness = 5
		light.Range = 50
		light.Parent = beam

		-- Sparking particles
		local attach = Instance.new("Attachment")
		attach.Parent = beam
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 180)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 80, 255)),
		})
		sparks.Size = NumberSequence.new(2, 0.3)
		sparks.Transparency = NumberSequence.new(0.1, 1)
		sparks.Lifetime = NumberRange.new(0.2, 0.5)
		sparks.Rate = 250
		sparks.Speed = NumberRange.new(60, 90)
		sparks.SpreadAngle = Vector2.new(15, 15)
		sparks.Parent = attach

		task.spawn(function()
			-- Flicker pattern: bright/dim alternation gives "electric" feel.
			-- Short total (~0.32s) so player can't outrun the beam by boosting.
			for i = 1, 8 do
				task.wait(0.04)
				beam.Transparency = if i % 2 == 0 then 0.15 else 0.5
				beam.Size = Vector3.new(70, 3 + i * 0.5, 3 + i * 0.5)
			end
			sparks.Enabled = false
			task.wait(0.15)
			beam:Destroy()
		end)

	elseif element == "Earth" then
		-- Rock armor: brown glow
		local glow = Instance.new("Part")
		glow.Shape = Enum.PartType.Ball
		glow.Size = Vector3.new(12, 12, 12)
		glow.Position = position
		glow.Color = Color3.fromRGB(139, 119, 80)
		glow.Material = Enum.Material.Neon
		glow.Anchored = true
		glow.CanCollide = false
		glow.Transparency = 0.4
		glow.Parent = game.Workspace

		task.spawn(function()
			for i = 1, 10 do
				task.wait(0.05)
				glow.Transparency = 0.4 + (i / 10) * 0.6
			end
			glow:Destroy()
		end)

	elseif element == "Dark" then
		-- Shadow: dark mist puff
		local mist = Instance.new("Part")
		mist.Shape = Enum.PartType.Ball
		mist.Size = Vector3.new(20, 20, 20)
		mist.Position = position
		mist.Color = Color3.fromRGB(30, 10, 40)
		mist.Material = Enum.Material.Neon
		mist.Anchored = true
		mist.CanCollide = false
		mist.Transparency = 0.3
		mist.Parent = game.Workspace

		task.spawn(function()
			for i = 1, 20 do
				task.wait(0.05)
				mist.Transparency = 0.3 + (i / 20) * 0.7
				mist.Size = Vector3.new(20 + i, 20 + i, 20 + i)
			end
			mist:Destroy()
		end)

	elseif element == "Light" then
		-- Heal pulse: white expanding ring
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(1, 10, 10)
		ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
		ring.Color = Color3.fromRGB(255, 255, 255)
		ring.Material = Enum.Material.Neon
		ring.Anchored = true
		ring.CanCollide = false
		ring.Transparency = 0.3
		ring.Parent = game.Workspace

		task.spawn(function()
			for i = 1, 15 do
				task.wait(0.04)
				local s = 10 + i * 6
				ring.Size = Vector3.new(1, s, s)
				ring.Transparency = 0.3 + (i / 15) * 0.7
			end
			ring:Destroy()
		end)
	end
end)

-- ================================
-- HUD UPDATE LOOP
-- ================================

RunService.Heartbeat:Connect(function(dt: number)
	-- Update health from humanoid (now synced by server)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			HUD.updateHealth(humanoid.Health, humanoid.MaxHealth)
		end
	end

	-- Update boost meter
	HUD.updateBoost(FlightController.getBoostPercent())

	-- Update cooldown indicators
	HUD.updateCooldowns(
		CombatInput.getBreathCooldownPercent(),
		CombatInput.getSpecialCooldownPercent(),
		CombatInput.getShieldCooldownPercent()
	)

	-- Sprint 6: round-timer text is now set by RoundStart (`Round N`) and
	-- RoundEnd (`Round Over!`). No per-frame decrement — the active round
	-- length is wave-driven, not a fixed clock, so a ticking number would
	-- mislead. WaveTracker is the canonical round-progress UI.

	-- Compass: project off-screen players + NPCs to the screen edge as arrows
	-- so the player always knows where to look for action. Cheap (~10 entities
	-- max, simple math) so safe to run every frame.
	Awareness.updateCompass()

	-- Lock-on validity check: clears the lock if target died, despawned, or
	-- moved out of cone/range. Cheap (~no-op when no lock is active).
	LockOnController.update()

	-- Zone-based music crossfade. ZoneManager (Sprint 5 Part C) is now the
	-- canonical source — replaces the previous Y>300 altitude heuristic.
	-- Default to Lair if the attribute hasn't replicated yet (matches the
	-- spawn-in-Lair behavior so the calm music plays first).
	local zoneAttr = player:GetAttribute("Zone")
	local inLair = zoneAttr == nil or zoneAttr == "Lair"
	SoundManager.setZone(inLair, dt)
end)

-- Hotkey handler. Tab is reserved by Roblox for the playerlist UI, so
-- lock-on uses F (standard fighter-game key). B opens Dragon Select.
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	-- Diagnostic for the F-key-not-working report: prints BEFORE the
	-- gameProcessed gate so we can tell if input is reaching us at all.
	-- If the F line never prints when the user presses F, the key isn't
	-- reaching this handler (likely a higher-priority binding). If it
	-- prints with gameProcessed=true, a UI element is consuming it
	-- (chat, leaderboard, focused TextBox, etc.).
	if input.KeyCode == Enum.KeyCode.F then
		print(`[Hotkey] F received. gameProcessed={gameProcessed}`)
	end
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.B then
		DragonSelectUI.toggle()
	elseif input.KeyCode == Enum.KeyCode.F then
		LockOnController.onLockKeyPressed()
	end

	-- Dismiss the shield tutorial popup the moment the kid presses the
	-- shield button (R on KB, X on gamepad). They learned the lesson —
	-- get the popup off the screen so it doesn't linger during combat.
	-- HUD.dismissShieldHint is idempotent so calling on every shield press
	-- after the first is harmless.
	if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonX then
		HUD.dismissShieldHint()
	end
end)

-- Persistent HUD hint so players know about the [B] hotkey without having
-- to discover it accidentally. Tucked in the top-left so it doesn't compete
-- with combat indicators.
do
	local hintGui = Instance.new("ScreenGui")
	hintGui.Name = "DragonsHint"
	hintGui.ResetOnSpawn = false
	hintGui.Parent = player:WaitForChild("PlayerGui")

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.fromOffset(180, 32)
	hint.Position = UDim2.fromOffset(20, 20)
	hint.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	hint.BackgroundTransparency = 0.3
	hint.BorderSizePixel = 0
	hint.Text = "[B] Switch Dragon"
	hint.TextColor3 = Color3.fromRGB(255, 215, 0)
	hint.TextStrokeTransparency = 0
	hint.Font = Enum.Font.GothamBold
	hint.TextSize = 16
	hint.Parent = hintGui

	local hintCorner = Instance.new("UICorner")
	hintCorner.CornerRadius = UDim.new(0, 6)
	hintCorner.Parent = hint
end

-- Sprint 7: bind the Lair Stat Stone's ProximityPrompt to open the
-- upgrade modal. Server creates the prompt under each tagged Stat Stone
-- in LairBuilder; we connect to its Triggered signal client-side.
-- CollectionService:GetInstanceAddedSignal handles late-build cases
-- (server still loading hero asset when this client init runs).
do
	local CollectionService = game:GetService("CollectionService")
	local STAT_STONE_TAG = "DragonWarz_StatStone"
	local function bindStatStone(part: Instance)
		local prompt = part:FindFirstChildWhichIsA("ProximityPrompt")
		if not prompt then return end
		prompt.Triggered:Connect(function(triggerPlayer: Player)
			-- Triggered fires for every player on a server-created prompt;
			-- only the local player should open their UI. Filter here.
			if triggerPlayer ~= player then return end
			DragonUpgradeUI.open()
		end)
	end
	for _, part in CollectionService:GetTagged(STAT_STONE_TAG) do
		bindStatStone(part)
	end
	CollectionService:GetInstanceAddedSignal(STAT_STONE_TAG):Connect(bindStatStone)
end

print(`[Client] {player.Name} Dragon Warz client ready!`)
