# Dragon Warz

Roblox aerial-combat PvP + PvE survival game. Luau + Rojo + Meshy AI 3D models +
Claude Code agentic workflow.

## Quick start (dev)

```bash
# 1. Install toolchain (Rojo, Wally, Lune, StyLua, Selene)
rokit install

# 2. Install Wally packages
wally install

# 3. Start the live-sync server
rojo serve

# 4. In Roblox Studio:
#    - Open the Dragon Warz place
#    - Plugins tab → Rojo → Connect (green = synced)
#    - Press F5 to playtest
```

## Quick start (deploy to Roblox)

```bash
# Test deploy (Saved — visible to you only)
lune run scripts/deploy.luau

# Live deploy (all players get it)
lune run scripts/deploy.luau --published
```

See [PUBLISHING.md](PUBLISHING.md) for one-time setup (Place ID + Universe ID
config, GitHub Actions secrets, Creator Hub checklist).

## Project structure

- `src/server/` — Server-authoritative game logic (combat, NPCs, data, rounds)
- `src/client/` — Per-player UI, input, camera, effects
- `src/shared/` — Configs and types shared by both sides
- `references/` — AI corpus for Claude Code (Roblox dev knowledge base)
- `scripts/` — Lune scripts: deploy, asset upload, migrations
- `assets/` — Audio + 3D models (gitignored — Meshy regenerates from prompts)
- `DESIGN.md` — Game design document (read first when picking up the project)
- `CLAUDE.md` — Claude Code workflow rules + tech stack
- `PUBLISHING.md` — Deploy checklist + GitHub Actions setup

## Tech stack

- **Engine**: Roblox Studio + Luau (strict mode)
- **Sync**: Rojo (filesystem ↔ Studio)
- **Packages**: Wally
- **Toolchain**: Rokit (pins versions per project)
- **3D Assets**: Meshy AI MCP server → Bridge → Roblox Creator Hub
- **CI/CD**: GitHub Actions + Lune + Open Cloud Place Publishing API
- **Audio**: Roblox Pro Sound Effects partnership assets + DistrokidOfficial music

## Controls

| Action | KB+M | PS5/Xbox |
|--------|------|----------|
| Move | WASD | Left Stick |
| Look / aim | Mouse | Right Stick |
| Up / down | Space / Shift | RB / LB |
| Boost | Q (hold) | A (hold) |
| Breath attack | Left Click | RT |
| Special ability | E or Right Click | LT |
| Open dragon menu | (auto on intermission) | Y |
| Zoom in/out | Mouse wheel | D-pad up/down |
| Menu navigate | Click | D-pad + A/B |

## Game systems

- **6 dragons** (Ember/Frost/Storm/Terra/Shadow/Prism) with unique stats + specials
- **120-second FFA rounds** with 15s intermission
- **Survival waves**: AI enemy dragons (Scout/Warrior/Boss) escalate every 30s
- **Lock-on aim assist** (kid-friendly, soft-snap within 30° cone)
- **Daily login + streak bonuses**, first-win-of-day +50 coins
- **Dragon select UI** during intermission with buy-with-coins progression
- **Round-end summary** with leaderboard + earned coins
- **Awareness HUD**: damage-direction arc + compass arrows for off-screen entities
- **Welcome banner** on join with streak progress

## Workflow

We use a multi-Claude collaboration workflow — different Claude sessions
take "sprints" (feature packs) and review each other's code before push. See
`CLAUDE.md` for AI workflow rules and `references/` for the Roblox dev knowledge
base each session loads.
