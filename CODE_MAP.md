# Dragon Warz — Code Map

Quick-reference dependency graph + "if you touch X, these things break" cheatsheet. Read this BEFORE editing anything in `src/`.

## Critical chain — the "everything depends on this" path

If any link in this chain fails, the whole game breaks:

```
1. NetworkSetup.setup()       creates Remotes folder
        ↓
2. Server require(...) chain  loads all server modules
        ↓
3. ArenaBuilder.build()       builds geometry
        ↓
4. Remote getters             grab references to RemoteEvents
        ↓
5. Players.PlayerAdded        per-player init: data + spawn + remotes
        ↓
6. Client requires + inits    UI, controllers, sound
        ↓
7. Client WaitForChild        waits for remotes to exist (30s timeout)
        ↓
GAME RUNS
```

**Failure modes** (each one looks like "game just doesn't work"):

| Failure point | Symptom | What to check |
|---|---|---|
| Step 2 require error | Server prints nothing, client times out on remotes, no music, no dragons | Output console for red text on require lines |
| Step 3 build error | Same as above (server init halts) | Wrap in pcall, paste the error |
| Step 5 PlayerAdded error | Specific player has issues, others OK | Check for warns about that player |
| Step 7 WaitForChild timeout | `[Client] Timed out waiting for Remotes folder` warn | Means server didn't create remotes — Step 1/2 failed |

## File dependency graph

### Server-side (`src/server/`)

```
init.server.luau  (entry — RUNS FIRST, errors here = total breakage)
├── NetworkSetup.luau         ← creates remotes (must run first)
├── DataManager.luau          ← persistence, daily login, retention
│   └── DragonConfig (shared) ← roster
├── CombatManager.luau        ← server-authoritative damage/HP
│   └── DragonConfig (shared)
├── RoundManager.luau         ← round timing, scoreboard
├── DragonSpawner.luau        ← character creation, mesh attach via Motor6D
│   └── DragonConfig (shared)
├── ArenaBuilder.luau         ← floating-island geometry
├── LairBuilder.luau          ← Crystal Lair (Sprint 5)
├── ZoneManager.luau          ← Sprint 5 Part C: Lair sphere test + Player.Zone attribute
├── DragonProgression.luau    ← Sprint 7: per-dragon stat upgrades, cost curve, atomic tryUpgrade
├── NPCManager.luau           ← AI dragons + Sprint 6 wave state machine (runWaveSequence)
│   └── EnemyConfig (shared)
└── RateLimiter.luau          ← per-player remote spam prevention
```

### Client-side (`src/client/`)

```
init.client.luau (entry — depends on remotes existing!)
├── FlightController.luau     ← WASD + mobile movement state
├── CameraController.luau     ← mouse-look, scroll zoom, FOV punch, applyLookDelta
├── CombatInput.luau          ← LMB breath / RMB special / element VFX projectile
│   └── LockOnController       ← reads lock target for aim assist
├── HUD.luau                  ← health, boost, coins, kill feed, special panel
│   └── DragonConfig (shared)
├── SoundManager.luau         ← SFX library + element-special-sound stacks + music
├── DragonSelectUI.luau       ← B-key menu, card grid, buy/select
│   └── DragonConfig (shared)
├── RoundEndSummary.luau      ← winner banner, leaderboard, coins earned
├── LockOnController.luau     ← F-key target acquisition + Highlight reticle
├── Awareness.luau            ← compass arrows + damage direction arc
├── WelcomeBanner.luau        ← daily login welcome popup
├── MobileControls.luau       ← touch joystick + buttons (only on mobile)
├── SafeZoneIndicator.luau    ← Sprint 5 Part C: "SAFE ZONE" pill, attribute-driven
├── WaveTracker.luau          ← Sprint 6: wave-state HUD (incoming / counter / clear / rest)
├── DragonUpgradeUI.luau      ← Sprint 7: stat-upgrade modal (multi-dragon tabs, preview, confirm)
└── LairAtmosphere.luau       ← Sprint 8: Lighting-tint crossfade on Lair / Arena zone change
```

### Shared (`src/shared/`)

```
Modules/
├── DragonConfig.luau         ← canonical 6 dragons + meshAssetIds
├── EnemyConfig.luau          ← Scout/Warrior/Boss stats
└── PlayerDataTemplate.luau   ← schema + defaults

Network/
└── RemoteNames.luau          ← string constants for remote names
```

## "If you touch X, these things might break"

### Adding a new server module
**Risk: 🔴 HIGH** — wrong order in init.server.luau breaks everything.

Safe pattern:
1. Create the module file (`src/server/MyNewModule.luau`)
2. Test it loads in isolation (require it, call simple methods, verify no error)
3. ONLY THEN add `require(script.MyNewModule)` to init.server.luau
4. Wrap any startup calls in pcall:
   ```lua
   local ok, err = pcall(MyNewModule.start)
   if not ok then warn(`[Server] MyNewModule.start failed: {err}`) end
   ```
5. Test in Studio with Output console open. If you see the warn, fix the error before removing the pcall.

### Adding a new RemoteEvent
**Risk: 🟡 MEDIUM** — must be added in TWO places or client times out.

Safe pattern:
1. Add name to `src/shared/Network/RemoteNames.luau`
2. Add to the `eventNames` table in `src/server/NetworkSetup.luau`
3. THEN write server-side handler (`remote.OnServerEvent:Connect`)
4. THEN write client-side `remotes:WaitForChild("...")` and `OnClientEvent:Connect`

### Adding a new Dragon
**Risk: 🟢 LOW** — just data.

Safe pattern:
1. Add entry to `src/shared/Modules/DragonConfig.luau`
2. Add `meshAssetId` if you have one
3. Add to `DRAGON_ORDER` in `src/client/DragonSelectUI.luau` so it shows in the grid
4. Add to special-effect handlers in `src/client/init.client.luau` (Fire/Ice/etc. blocks) if it's a new element
5. Add to `SoundManager.SPECIAL_SOUNDS_BY_ELEMENT` if new element

### Adding a new HUD element
**Risk: 🟢 LOW** — additive, can't break others.

Safe pattern:
1. Edit `src/client/HUD.luau`, add to the `HUD.create()` function
2. Use a clear ZIndex if it overlaps anything (1=bg, 5=overlays, 10+=modals)

### Editing combat damage / hit detection
**Risk: 🔴 HIGH** — affects PvP balance + NPC AI.

Touch ONLY:
- `src/server/CombatManager.luau` for damage rules / falloff / regen
- `src/server/init.server.luau` fireBreathRemote handler for the breath cone test

Don't touch unless you know:
- `src/server/NPCManager.luau` AI tick / damage callbacks (Combat depends on it being unchanged)

### Editing mesh / dragon visual
**Risk: 🟡 MEDIUM** — can break Motor6D wobble + camera.

Touch:
- `src/server/DragonSpawner.luau` for spawn logic
- `src/shared/Modules/DragonConfig.luau` for `meshAssetId` / `meshScale`

DON'T break:
- The Motor6D between body and MeshAnchor (FlightController + Awareness drive it for wobble)
- The HumanoidRootPart name or PrimaryPart assignment (camera + flight follow it)

## Pre-commit checklist for any server module change

Before you commit anything in `src/server/`:

- [ ] Studio playtest: F5, watch Output for any red errors
- [ ] Verify music plays on join (proves client got remotes)
- [ ] Press B → DragonSelectUI opens (proves client init worked)
- [ ] Spawn flies, breath fires (proves PlayerAdded ran fully)
- [ ] At least 30 seconds of playtest before stopping (catches AI tick errors)

If any of those fail, don't commit — fix or revert first.

## When the game "just doesn't work"

The fast diagnostic flow:

1. **Studio Output console** (View → Output) — red text shows the actual error
2. **Rojo terminal** — is it green/connected? Is it showing recent sync lines?
3. **Stop playtest, try fresh F5** — sometimes Studio caches stale code
4. **Check git log** — what commits landed since last working state? Bisect by reverting one at a time.
5. **The pcall trick** — wrap suspicious init code in `pcall(function() ... end)` with a `warn` on failure. Game keeps running, error gets logged.

## What I (Claude) should do differently going forward

After the Sprint 5 Part A breakage:

1. **Always pcall new init code** on first integration. Remove the pcall only after I've watched Output console show successful prints.
2. **Test require in isolation** before integrating. Studio command bar can do this: `require(game.ServerScriptService.Server.LairBuilder)` and check for errors.
3. **Smaller integration steps**. Don't add a new module + a new server-init call + 200 lines of code in one commit. Add the file alone, verify it loads, then wire in.
4. **Read this code map** before touching anything in init.server.luau or init.client.luau — those two files are the most fragile.

### Recurring footgun: paren-prefix ambiguous syntax

This bug class has now bitten us twice (HUD.luau Sprint 5, DragonProgression.luau
Sprint 7). Luau's parser reads a line starting with `(` as a function-call
argument list applied to the previous expression's result.

```lua
-- BROKEN: Luau parses this as `cost(levels :: any)[statKey] = current + 1`
data.coins -= cost
(levels :: any)[statKey] = current + 1

-- FIXED: bind the cast to a concrete local so the next line starts with a name
local levelsAny = levels :: any
data.coins -= cost
levelsAny[statKey] = current + 1
```

Also bites with `Instance.new(...)` followed by a `(cast):Property = ...` line.
Whenever you write a line that starts with `(`, either:
- Hoist the parenthesized expression to a local first, OR
- Add an explicit `;` at the end of the previous line, OR
- Reorder so the line doesn't start with `(`.

Before committing any module that uses `(x :: SomeType)` or `(Instance.new("X"))`
on its own line, grep for `^\s*\(` in the new code and verify each isn't
preceded by an expression-returning statement.
