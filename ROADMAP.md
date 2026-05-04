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

### Sprint 6 — Wave Structure with Rests (~3-4 hours)
- Refactor NPCManager wave loop: 3 waves with 15s breaks between
- Visual countdown UI: "Wave 2 starts in 15s"
- Round-end summary shows wave-by-wave breakdown
- Fewer NPCs total, but punchier waves with rest

### Sprint 7 — Dragon Progression UI in Lair (~10-12 hours)
- Stat board: see your dragon's level, XP bar, current stats
- Upgrade station: spend coins on Atk/Def/Spd/Special points
- Practice dummies: test your damage on harmless NPCs
- Save progression in DataManager (extend PlayerData schema)

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
| C | ZoneManager (Region3 zone detection) | ⏳ NOT STARTED — currently spatial separation handles safety accidentally |
| D | Combat-zone gating (NPCs ignore Lair, PvP gated) | ⏳ NOT STARTED |
| E | Portal teleport (both directions) | ✅ shipped |
| F | Spawn in Lair (default + post-death) | ✅ shipped (after recursion-bug hotfix `d58d1e3`) |

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

1. **QA the current loop**: F5, spawn in Lair, walk through portal, fight, return portal, die, respawn in Lair. Confirm all four steps work.
2. **Sprint 5 Parts C+D**: explicit zone enforcement. Currently the Lair is "safe by accident" because NPCs can't reach it spatially, but explicit gating is more robust.
3. **After C+D**: push the entire Sprint 5 stack, then move to Sprint 6 (wave rest structure) or Sprint 7 (dragon progression UI in Lair) — whichever the QA playtest reveals as more urgent.

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
