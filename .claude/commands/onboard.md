---
description: Brief a fresh Claude session on this Roblox project's framework, current state, and conventions. Run at the start of any new session.
---

You're being onboarded to a Roblox game development project that uses our shared **Dragon Warz framework**. Get up to speed by reading these files in order, then summarize.

## Step 1: Project rules + framework
Read in this order:
1. `CLAUDE.md` — project setup, tech stack (Luau + Rojo + Wally + Lune), AI workflow rules ("AI handles code/logic, human handles visuals/QA")
2. `CODE_MAP.md` — **REQUIRED**. Dependency graph + "if you touch X, these things break" cheatsheet. Read before editing ANY server module.
3. `DESIGN.md` — game design (current spec or template for new game)
4. `SKILL.md` — Roblox SDK reference router (which `references/<file>.md` to read for which task)
5. List `references/` so you know what specialized docs are available

## Step 2: Current state
1. `git log --oneline -20` — recent work, sprint history
2. `git status` — uncommitted changes, current branch
3. Check if a `MEMORY.md` or auto-memory exists at `~/.claude/projects/c--Users-howar/memory/MEMORY.md` for cross-session context

## Step 3: Code orientation
Survey but don't deep-read:
- `src/server/init.server.luau` — server entry, wires up all systems
- `src/client/init.client.luau` — client entry, wires up all UI/input modules
- `src/shared/Modules/` — DragonConfig, EnemyConfig, PlayerDataTemplate
- `src/shared/Network/RemoteNames.luau` — canonical remote event names

## Step 4: Briefing output
After reading, summarize for the user:
- **Project name + concept** (one line)
- **What's shipped** — last 5-10 commits
- **What's pending QA or deferred** — anything in flight
- **Key conventions to respect**:
  - `.luau` files in `src/` map to Roblox instances via Rojo
  - `.client.luau` = LocalScript, `.server.luau` = Script, `.luau` = ModuleScript
  - Server-authoritative for combat/data; client-side for prediction/UI
  - Commit each logical change separately so QA can revert specific items
  - Don't push without explicit user approval
- **Suggest ONE concrete next action** based on the open backlog. Wait for user confirmation before starting.

## Hard rules to surface immediately
- **MCP servers configured** — Roblox Studio MCP + boshyxd robloxstudio-mcp + Meshy MCP. If user wants 3D assets, suggest the Meshy pipeline.
- **Rojo serve flow** — code lives on disk, Rojo syncs to Studio. If the user reports "changes aren't applying," it's almost always Rojo not connected (green light in Studio Plugins → Rojo).
- **Multi-Claude collaboration** — different sessions take "sprints" and review each other's work. If you find code you didn't write, it's peer Claude. Don't revert without checking.
