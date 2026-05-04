# Dragon Warz — Roadmap & Vision

> The shared brain across Claude sessions. Read this BEFORE starting work, especially after a context compact or in a fresh session.

## The core insight

Drop a kid into a 120s chaos battle with no on-ramp = they bounce in 60 seconds and never come back. Every successful Roblox kid game has a "home" + "danger" loop:

| Game | Home | Danger |
|---|---|---|
| Adopt Me | Nursery | Adventure World |
| Pet Sim | Hub | World |
| Brookhaven | Safe city | Combat zones (optional) |

Dragon Warz needs the same architecture.

---

## The 3-Zone Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   🏠 LAIR (Safe Hub)                                        │
│   • You spawn here                                          │
│   • NPCs CANNOT enter                                       │
│   • PvP disabled                                            │
│   • Manage dragon: upgrade stats, switch dragon             │
│   • Practice dummies for testing breath/special             │
│   • Trophy display (your wins, dragons unlocked)            │
│   • Portal/door to Arena                                    │
│                                                             │
│              [STEP THROUGH PORTAL]                          │
│                       ↓                                     │
│                                                             │
│   ⚔️ ARENA (Combat Zone)                                    │
│   • PvP active                                              │
│   • NPCs spawn in waves with breaks                         │
│   • Wave 1 (Easy) → Rest (15s) → Wave 2 (Medium)            │
│     → Rest → Wave 3 (Hard with Boss) → Round End            │
│   • Portal back to Lair when done                           │
│                                                             │
│              [INSTANCED ENTRY]                              │
│                       ↓                                     │
│                                                             │
│   🐉 DUNGEONS (Phase 6, later)                              │
│   • 1-3 player co-op                                        │
│   • Single-boss encounters                                  │
│   • Rare loot drops                                         │
│   • Daily reset                                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Player Journey: Beginning → Middle → End

### 🌱 Beginning (first session, ~10-15 min)
1. Spawn in Lair — peaceful floating island, soft music
2. Welcome banner: "Welcome to Dragon Warz! This is your Lair. Practice here, then step through the portal when you're ready to fight."
3. Tutorial nudges (optional):
   - "Click the Practice Dummy to try your breath attack"
   - "Walk to the Upgrade Stone to power up your dragon"
   - "Step through the glowing portal to enter the Arena"
4. First Arena visit: Wave 1 only (3 Scouts, easy). Win = 50 coins + first kill XP
5. Return to Lair: spend coins, see stats grow, feel powerful

### 🎯 Middle (sessions 2-20)
- Daily login bonus in Lair (shipped)
- Loop: Lair (manage) → Arena (fight) → Lair (upgrade) → Arena (fight harder)
- Progression: dragon levels 1-50, unlock stats, new dragons
- Variety: try different elements, find your favorite playstyle

### 🏆 End (long-term)
- Mastery: max-level dragons, all 6 unlocked
- Dungeons: PvE bosses with rare loot (Phase 6)
- Prestige: reset for permanent buffs
- Tournaments: leaderboard competitions
- Social: visit friends' lairs (Phase 7)

---

## Problems this fixes

| Current problem | Lair fix |
|---|---|
| "I don't know what's happening" | First-time tutorial in safe space |
| "I keep dying immediately" | Lair is safe, you choose when to fight |
| "I don't see my progression" | Stat board in Lair shows numbers going up |
| "Combat is exhausting" | Rest in Lair between rounds, not every 2 minutes of chaos |
| "I don't know how to upgrade" | Dedicated upgrade station with clear UI |
| "First impression is overwhelming" | Calm spawn + visible portal to opt-in to combat |

---

## Sprint plan (4-5 sprints to land the full vision)

### Sprint 5 — Build the Lair + Zone System (~6-8 hours)
The foundation. Without this nothing else works.

- New Lair area (separate floating island ~300 studs from current arena)
- Portal between Lair → Arena
- Player spawns in Lair instead of arena
- NPCs can't see / target players in Lair (zone check in NPCManager)
- PvP disabled in Lair (zone check in fireBreath handler)
- Visual indicator: "Safe Zone" label when in Lair

### Sprint 6 — Wave Structure with Rests (~5-7 hours) ✅ shipped

Use case: kids were burning out in 2-minute continuous-chaos rounds.
Replaced with a fight → rest → fight rhythm so adrenaline drops between
beats and kids feel structured progress.

- ✅ NPCManager: `runWaveSequence` state machine (INCOMING → ACTIVE →
  CLEARED/TIMEOUT → RESTING) replaces the old continuous wave spawn loop.
  Three waves per round: easy (3 scouts), medium (4 scouts + warrior),
  boss (1 boss + 2 scouts). 90s wave timeout, 15s rest between, 240s
  round safety cap.
- ✅ RoundManager: dropped the strict 120s round duration. Round length
  is now wave-driven; safety cap counts down in the background. Three-
  callback API (`onRoundStart`, `onActivePhase`, `onRoundEnd`).
- ✅ Per-wave coin payout (30 / 50 / 100) to all players who are alive
  AND in the Arena when each wave clears — Lair-hiders skip the bonus.
- ✅ Client `WaveTracker.luau`: top-center state-aware pill (incoming
  banner / enemy counter / clear flash / countdown). Self-contained
  ScreenGui (HUD-isolation pattern from Sprint 5).
- ✅ Round-end summary: per-wave breakdown row ("✅ W1 22s · ⏱️ W2 — ·
  ✅ Boss 35s") so kids see exactly how far they got.
- ✅ First-rest "💡 Tip: portal to your Lair to catch your breath!"
  subtitle, once-per-session.
- ✅ HUD round-timer repurposed to "Round N" — WaveTracker is now the
  canonical round-progress UI; the safety-cap clock isn't surfaced to
  avoid misleading the kid with a 240s number.

**Sprint 6 playtest fixes (post-first-playtest):**
- ✅ **Server-boot ghost-player bug** — `Players.PlayerAdded:Connect`
  ran AFTER the slow `ArenaBuilder.build()` + `LairBuilder.build()`
  InsertService loads. The player whose join triggered server boot
  fired PlayerAdded before the handler attached, became a ghost (no
  leaderstats, no DataManager entry, no `state.scores` row, no spawn).
  At round-end: "No Winner", empty leaderboard, 0 coins. Fixed by
  factoring the handler into `processPlayer` and adding a catch-up
  loop that `task.spawn`s `processPlayer` for any pre-attached players.
- ✅ **15-second purple-screen wait on first join** — RoundManager's
  startLoop began with a 15s intermission unconditionally, so the kid
  triggering server boot stared at nothing for 15s before round 1.
  First iteration now skips the intermission; subsequent intermissions
  still run (they're when DragonSelectUI opens between rounds).
- ✅ **WaveTracker pill overlapping HUD "Round N" text** — HUD's
  ScreenGui doesn't set `IgnoreGuiInset` (default false, content offset
  by Roblox's top status bar) but WaveTracker had `IgnoreGuiInset =
  true`. On systems with the status bar showing, the two pills crashed
  into each other. Now both respect the inset and there's a clean 20px
  gap between them.

**Sprint 6 audit follow-ups (post-review):**
- ✅ Closure-captured `spawnedCount` / `spawnDone` in `runWaveSequence`.
  Fixes: counter going UP after a kill during the spawn-stagger window,
  false-clear race when a max-stat dragon blitzes scouts before the
  warrior spawns, and silent miscounts when MAX_NPCS = 12 caps a spawn.
- ✅ `enemiesLeft = alive + (totalEnemies - spawnedCount)` while spawning,
  collapsing to `alive` once `spawnDone`. Numerator only ever decreases
  on a kill.
- ✅ Boss pre-warn during RESTING: when `nextWave == NUM_WAVES`, the rest
  pill switches to red "⚠️ BOSS WAVE in {N}s..." instead of the calm
  yellow "Wave 3 starts in {N}s..." countdown.
- ✅ Wave-clear audio: `SoundManager.play("Coin")` layered on the green
  flash for the audible-reward beat.

Audit findings deferred / declined:
- "Mid-round joiner gets coins but no scoreboard credit" — incorrect.
  `RoundManager.initPlayerScore` IS called from `Players.PlayerAdded`
  (init.server.luau:164), so the joiner has a `state.scores` entry from
  the moment they connect. `recordCoins` works.
- `RoundManager.getWinner` returning a winner with 0 kills — pre-existing
  (Sprint 6 just makes solo-PvE rounds more common, exposing it more
  often). Not a Sprint 6 regression. Flagged for a later round-system
  cleanup pass.

### Sprint 7 — Dragon Progression UI in Lair (~9-11 hours) ✅ shipped

Use case: Sprint 6 promised "💡 visit your Lair to catch your breath!" but
the Lair was decorative — obelisks did nothing, dummies didn't react. Kids
followed the tip and bounced. Sprint 7 makes the visit meaningful: spend
coins on per-dragon stat upgrades, see your dragon's level grow, test new
damage on practice dummies. Closes the dopamine loop: earn coins → buy
upgrade → test on dummy → see bigger number → fight harder.

- ✅ `DragonProgression.luau`: per-dragon stat upgrades (Atk / Def / Spd /
  Special), 5 levels each, cost curve 25/100/200/400/800 (peer audit
  rebalance — first rank cheap enough to taste in round 1, exponential
  from there). Spd uses diminishing returns 5/3/3/2/2 = +15 max so it
  doesn't break PvE/PvP balance. Atomic `tryUpgrade` with per-player
  upgrade-in-flight lock (anti-double-click race) + force-save +
  rollback on save failure.
- ✅ Per-dragon upgrades (not shared) — gives each dragon identity and
  ongoing reasons to spend coins beyond unlocking new dragons. Mastery
  cross-dragon scaling deferred until playtest reveals if rebuilds are
  actually painful.
- ✅ `CombatManager.applyLiveStatChange`: a kid who upgrades mid-round
  (Lair retreat → buy → portal back) sees the buff immediately, no
  death/respawn required. Health upgrades bump maxHealth + heal the
  delta; damage upgrades affect the next breath; speed flows through
  `DragonStatsUpdated` → `FlightController` cache.
- ✅ All combat damage paths (fireBreath, useSpecial Fire/Lightning) read
  state.damage / state.specialDamage so upgrades flow through.
- ✅ `DragonUpgradeUI.luau`: modal panel with multi-dragon tabs (kids own
  multiple dragons, can upgrade any of them without leaving the Lair),
  per-stat row with current value + level dots + upgrade button + stat
  preview "Lv N → N+1: 15 → 20", MAX badge, confirmation prompt for
  purchases ≥200 coins, first-visit tutorial hint.
- ✅ Lair Stat Stone: tagged + ProximityPrompt (range 6, RequiresLineOfSight)
  → opens the upgrade modal client-side.
- ✅ Lair Shop Stone: tagged + "🔒 Coming Soon" sub-label so kids who walk
  up to it don't bounce off thinking it's broken (Sprint 9 wires it up).
- ✅ Practice dummies: HP state + hit-detection API + KO/respawn loop.
  Sprint 5 Part D fireBreath gate now has a narrow Lair-only carve-out
  routing breath cones to dummy-damage (committed separately for
  blast-radius isolation).
- ✅ HUD: "Lv N" badge next to dragon-name label so a kid who spent 800
  coins on Atk Lv 5 sees their progression in combat (otherwise the
  upgrade is invisible during gameplay — peer #2).
- ✅ `WaveTracker` rest-period tip now points at the Stat Stone explicitly.
- ✅ STUDIO_MAXED_UPGRADES toggle for combat-balance testing;
  STUDIO_FRESH_PLAYER takes precedence so the new-player flow stays QA-able.
- ✅ Persistence: `PlayerData.dragonUpgrades` + `hasSeenLairTutorial` fields,
  deepMerge migration handles pre-Sprint-7 saves.

Audit findings deferred (revisit post-QA):
- #11 affordability sparkle on coin counter (polish-on-polish)
- #14 Mastery cross-dragon scaling (wait for playtest data on rebuild pain)
- #17 deepMerge migration manual verification with a real pre-Sprint-7 save

### Sprint 8 — Lair Glow-up (~4 hours) ✅ shipped

Use case: Sprint 7 made the Lair MEANINGFUL (Stat Stone, dummies,
upgrade modal) but it still read as static decoration. Kids spend
30s+ per round in the Lair plus full intermissions; a static
environment burns boredom into all that hub time. Goal: Lair becomes
a destination kids LOOK FORWARD to returning to.

Shipped in 5 incremental commits so each visual layer can be
reviewed and reverted independently:

- ✅ **Central Crystal Tower glow-up** — continuous slow Y-rotation,
  color-cycling apex PointLight (Fire→Ice→Lightning→Earth→Dark→Light
  loop on 18-second cycle), vertical 100-stud pillar-of-light beam,
  rising-sparkle particle aura at base.
- ✅ **Ambient floating motes** — 30 small Neon spheres drifting
  through the Lair air with random-walk paths + independent fade
  cycles. Element-color rotation. Fills the empty volume between
  pillar and arches.
- ✅ **Element arches polish** — pulsing PointLights inside each of the
  6 arch crystals (each on a 0.5s phase offset so they form an
  organic chorus), themed ground glow disc under each arch, walk-
  through particle bursts when player stands on the disc (per-player
  2-second cooldown so loitering doesn't spam particles).
- ✅ **`LairAtmosphere.luau` client module** — crossfades global
  Lighting (Ambient / OutdoorAmbient / FogColor / FogEnd) toward
  purple-gold magical-realm tint when in the Lair, restores Studio
  baseline when in the Arena. Crossfade matches music transition pace.
- ✅ **Stat Stone ground rune circle** — concentric pulsing rings +
  counter-rotating glyph slab around the obelisk. Visible across the
  Lair as a "magical interaction point."
- ✅ **Practice dummy element variety** — three dummies are now Fire /
  Ice / Lightning themed with colored bodies + floating accent orbs +
  element-themed particle wisps + element-named billboards. Sets up
  future damage-type mechanics; cosmetic for now.

Tier 3 deferred:
- Custom Lair skybox swap (heavy art, needs Roblox asset)
- Background ambient sound layer (chimes, wind hum)
- Dragon idle animations (more wing-flap variation when not moving)
- Portal arrival flash effect (would need a new remote)

### Sprint 9a — Analytics baseline (~1.5 hours) ✅ shipped

Use case: game is published with kids playing. Sprint 10 (Boss Waves)
needs a baseline funnel to measure against. Decision: ship analytics
NOW so by the time Boss Waves launches, we can see "did boss waves
move retention" with real before/after data — not guess.

Funnel events shipped:
- `SessionStart` / `SessionEnd` (with sessionLength) / `FirstSession`
  (only on the kid's first-ever join)
- `WaveCleared` (waveNumber, isBossWave)
- `RoundCompleted` (roundNumber, didWin, kills, coinsEarned) +
  `RoundWon` for the winner specifically
- `StatUpgraded` (dragonId, statKey, newLevel, coinsCost)
- `DragonUnlocked` (dragonId, coinsCost, viaShop=false for now)

Sprint 10 placeholders scaffolded (no-op until Boss Waves ship):
- `BossEncountered` (bossName, roundNum)
- `BossDefeated` (bossName, roundNum, damageContribution, coinReward)
- `BossTimedOut` (bossName, roundNum, hpRemainingPercent)

Implementation:
- `Analytics.luau` server module wraps `AnalyticsService:LogCustomEvent`
- Per-player session bookkeeping (sessionId + joinTimeOs) injected
  into every event's customFields so the dashboard can group by session
- All calls wrapped in pcall so a logging failure can never crash a
  gameplay path
- Studio mode mirrors events to Output console instead of dashboard
  (which is a no-op in Studio anyway) so devs can see the event flow
- Auto-cleanup via Players.PlayerRemoving so a crashed-out player
  doesn't leak their session record

### Sprint 10 — Boss Waves: BLAZE THE INFERNO LORD (~10-12 hours) ✅ shipped

Use case: Sprint 7 made the player progress (stat upgrades). Sprint 8
made the world look alive. Sprint 9a gave us the analytics. Sprint 10
adds architectural progression to the WORLD content — every 3rd round
breaks the circular wave-3-and-done pattern with a multi-mechanic boss
encounter. Word-of-mouth driver: "Did you beat Blaze yet?"

Shipped in 6 incremental commits + this docs commit:

- **(1/7) Boss data layer** — EnemyConfig.Blaze entry (800 HP base ×
  playerCount, deep-red tint, Storm-mesh-upscaled-12 visual, 25 dmg
  per telegraph), PlayerData.stats.bossesDefeated persistent stat,
  BossManager.luau skeleton with single-instance invariant +
  damageByUser map.
- **(2/7) Telegraph remote + client renderer** —
  BossTelegraph.luau renders red circle (InfernoSlam) + line preview
  (MagmaBeam) with 1.5-1.8s windups tuned for kid Xbox reaction time.
  Visual hitbox slightly wider than damage hitbox so dodging feels fair.
- **(3/7) Mega-Boss-Round cadence** — runWaveSequence takes
  roundNumber, appends a Mega-Boss wave on rounds where roundNumber %
  3 == 0. Polling loop waits for boss death (HP=0) or 90s fight
  timeout. Defensive cleanup catches round force-end races.
- **(4/7) Boss AI + player damage routing** —
  BossManager.tryHitWithCone exposes the boss for fireBreath / Fire
  vortex / Lightning chain hit detection (mirrors findHitNPC pattern).
  Boss AI tick alternates Inferno Slam (30-stud radius, 35 dmg) +
  Magma Beam (80-stud line, 30 dmg) every 5s. Each attack picks a
  random alive Arena player as target.
- **(5/7) Rewards + persistence + timeout flow** — defeat callback
  pays 50 flat + 300 damage-share to each contributing player,
  increments bossesDefeated stat, fires Analytics.bossDefeated.
  Timeout callback fires Analytics.bossTimedOut + "BLAZE ESCAPES"
  banner. Failure path pays nothing (peer audit: learning loop).
- **(6/7) Boss banner UX + music swap** — WaveTracker handles
  INCOMING / WARNING / DEFEATED / TIMEOUT states with distinct
  themes. WARNING state runs a per-second countdown ("BLAZE ESCAPING
  IN Ns") on its own thread, cancellable on state change.
  SoundManager.setBossMusicActive pitch-shifts arena music 1.0 → 1.3
  during the encounter (peer audit: pitch-shift carries enough
  signal for MVP, no new asset upload).

Stage 1.5 (deferred — gated on Sprint 10 analytics showing engagement):
- Frostmaul (Ice) and Voltrix (Lightning) reskins of the Blaze template
- Multi-phase boss AI (phase transitions at HP thresholds)
- Per-boss elemental weaknesses (Fire dragon vs. Ice boss does +25%)
- Bosses Defeated leaderboard / B-menu badge
- More attack patterns per boss (3 instead of 2)

### Sprint 8 — First-time Tutorial (~4-5 hours)
- Detect first-ever join (`data.totalLogins == 1` — peer Claude already tracks this)
- Quest-style nudges: "Try breath attack on the dummy" → "Step through the portal"
- One-time only; subsequent logins skip
- Skippable button for returning players who change devices

### Sprint 9 — Monetization + Analytics (~6-8 hours)
- Game passes (Unlock All Dragons, 2x Coins, VIP)
- Dev products (coin packs, instant revive)
- Analytics hooks: track Lair time, Arena time, conversion funnel
- Shop UI accessible from Lair

**Total estimate**: ~30-40 hours, ~4-5 weeks at sustainable pace.

---

## Decisions locked in

1. **Lair location**: same place file (Lair at `(2000, 500, 0)`, Arena at origin). Teleport via portal. Switch to separate places only if perf demands it later.
2. **Lair PvP**: fully disabled. Opt-in duels can come later if asked.

---

## Sprint 5 — current status

| Part | Description | Status |
|---|---|---|
| A | Build the Lair (LairBuilder.luau) | ✅ shipped + integrated |
| B | Sky Kingdom Arena (towers, clouds, castle) | ✅ shipped |
| Hero assets | Wired guard tower, wizard tower, crystal tower, obelisks, sky castle, atmosphere, grass base | ✅ shipped |
| Lair grounding | Underbase + tapered bottom + ambient clouds | ✅ shipped |
| C | ZoneManager (sphere-based Lair test, `Player:GetAttribute("Zone")` 5Hz tick) | ✅ shipped |
| D | Combat-zone gating (NPCs ignore Lair, PvP gated, breath/special/shield no-op in Lair) | ✅ shipped |
| E | Portal teleport (both directions) | ✅ shipped |
| F | Spawn in Lair (default + post-death) | ✅ shipped (after recursion-bug hotfix `d58d1e3`) |
| UI | "🏠 SAFE ZONE" pill while in Lair (top-center pill, attribute-driven) | ✅ shipped |

### Outstanding bugs / cleanup

- `GetPlayerData` race fix (welcome banner / streak badge) — peer Claude domain
- Blazing fire asset `10383034781` — placement TBD (castle apex? Lair torches?)
- ~18 commits stacked locally on `main`, NOT pushed to origin

### Big design ideas raised but not yet built (~half-day each)

**Castle-as-Lair**: replace the programmatic Lair geometry with the floating
castle asset `108721507426018` so the Lair IS the castle. Practice dummies,
upgrade obelisk, shop obelisk, portal all reposition around/inside the castle.
Arena loses its centerpiece — would need a different asset there.

**Humanoid-in-Lair, Dragon-in-Arena**: in the Lair, player is a default
Roblox humanoid (walk with WASD, default camera, click obelisks to interact).
On portal-step, transform into the selected dragon for Arena combat. Reverse
on Arena→Lair. Touches: zone detection, character model swap, camera
switching, input handler switching, stat persistence across transition.

Lair calm music: `83298024686703` (Rainy Window) shipped for both zones in
commit `29398c1`. Future work: zone-aware switching with combat music in
Arena (needs ZoneManager Part C).

### Next concrete sprint actions

1. **QA Sprint 5 Lair safe zone** (still pending):
   - "🏠 SAFE ZONE" pill visible top-center while standing in the Lair
   - LMB/Special/Shield keys do nothing in the Lair (no cooldown burned)
   - Portal to Arena → pill disappears, combat works
   - NPC at the edge of Arena does NOT chase a Lair-side player

2. **QA Sprint 6 wave rhythm**:
   - Round starts → "WAVE 1 INCOMING" banner, 3-second telegraph
   - Spawn 3 Scouts; "Wave 1 — N / 3 enemies" counter ticks down on kills
   - All Scouts dead → green flash + "✅ WAVE 1 CLEAR! +30 coins"
   - "Wave 2 starts in 15s..." countdown, first-time tip "💡 portal to Lair" appears
   - Wave 2 = 4 Scouts + 1 Warrior, +50 on clear
   - Wave 3 = "⚠️ BOSS WAVE INCOMING ⚠️", Boss + 2 Scouts, +100 on clear
   - Round-end summary shows wave-by-wave row "✅ W1 · ✅ W2 · ✅ Boss"
   - Lair-hider during a wave: does NOT receive the wave-clear coin bonus
   - Portal to Lair mid-wave: NPCs lose target instantly (Sprint 5 Part D)
   - Wave 3 cleared early → round ends within ~2 seconds (no 120s timer wait)

3. **After QA**: Sprint 7 (Dragon Progression UI in Lair — stat upgrades,
   practice dummies become functional) or Sprint 8 (FTUE for first-ever
   joiners). The Lair tip in Sprint 6 promises stat upgrades; Sprint 7
   delivers them.

---

## Reference docs

- `CLAUDE.md` — project rules, AI workflow
- `DESIGN.md` — game design (Dragon Warz spec)
- `CODE_MAP.md` — dependency graph + safe-edit guide (REQUIRED reading before server changes)
- `SKILL.md` — Roblox SDK reference router
- `ROADMAP.md` — this file (vision + sprint state)
- `.claude/commands/onboard.md` — fresh-session briefing slash command

---

## Lessons learned from earlier sessions

1. **Always F5 + check Output before "shipped"** — caught the HUD.luau syntax bug + LairBuilder integration crash.
2. **Wrap new init code in pcall on first integration** — keeps the game playable while we diagnose.
3. **Never `replace_all` on a token that appears inside the new function's body** — caused the `spawnInLair` infinite recursion. Use targeted edits or rename the helper to a unique token first.
4. **The Lair was a red herring early** — when "the game broke," it was actually a syntax error in HUD.luau (peer Claude commit) that masked any real Lair issues. Diagnose with Output console first, not by reverting recent work blindly.
