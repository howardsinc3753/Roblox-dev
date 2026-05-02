# Roblox Game Dev — Claude Code Project

## Project Overview
Roblox game development project using Luau, Rojo filesystem sync, and Claude Code AI workflow.
The game design lives in `DESIGN.md` — read it at the start of every session.

## Tech Stack
- **Language**: Luau (Roblox's typed Lua fork)
- **Editor**: Roblox Studio (visual) + VS Code (code)
- **Sync**: Rojo (filesystem ↔ Studio bridge)
- **Package Manager**: Wally
- **Toolchain Manager**: Rokit (pins tool versions in `rokit.toml`)
- **Linter**: Selene
- **Formatter**: StyLua
- **Testing**: Jest-Lua
- **Standalone Runtime**: Lune (build/deploy scripts)

## Project Structure
```
src/
├── shared/          → ReplicatedStorage (runs on both client and server)
│   ├── Modules/     → Game logic modules
│   └── Network/     → RemoteEvent/RemoteFunction definitions
├── server/          → ServerScriptService (server authority)
└── client/          → StarterPlayerScripts (client-side)
references/          → AI corpus docs (environment, languages, MCP, etc.)
scripts/             → Lune scripts for deploy, asset upload, migrations
tests/               → Jest-Lua test specs
assets/              → Audio, models, textures (raw source files)
voiceover/           → ElevenLabs TTS pipeline (lines.json + generated MP3s)
build/               → Rojo build output (gitignored)
```

## File Conventions
- `.luau` → ModuleScript (default)
- `.server.luau` → Script (runs on server)
- `.client.luau` → LocalScript (runs on client)
- `init.luau` inside a folder → folder becomes a script instance
- `*.spec.luau` → Jest-Lua test files (in `tests/`)

## Key Roblox Patterns
- Always cache services at top of file: `local Players = game:GetService("Players")`
- Use `task.wait()`, `task.spawn()`, `task.defer()` — never legacy `wait()`, `spawn()`
- Validate ALL RemoteEvent payloads server-side (client is hostile)
- Use `pcall` for anything that can yield/fail (DataStore, HTTP, etc.)
- Store connections and `:Disconnect()` them on cleanup (use Trove pattern)
- Use `--!strict` mode for type checking

## AI Workflow Rules
- Read `DESIGN.md` before starting any feature work
- AI handles: server scripts, modules, data structures, RemoteEvent wiring, datastore code
- Human handles: 3D placement, lighting, materials, particles, animation tuning
- MCP can't see Studio's viewport — visual bugs need human eyes
- Write code on disk in `src/` → Rojo syncs to Studio → MCP verifies at runtime
- Keep modules small and testable (dependency injection over `game:GetService` inline)

## Commands
- `rojo serve` — start live-sync to Studio
- `rojo build -o build/game.rbxl` — build place file
- `wally install` — install packages
- `stylua src/` — format code
- `selene src/` — lint code
- `lune run scripts/<name>` — run a Lune script

## References
Detailed docs for each domain live in `references/`:
- `environment.md` — setup, Rojo, Wally, Rokit, folder layout
- `languages.md` — Luau syntax, types, patterns, anti-patterns
- `ai-and-mcp.md` — MCP server setup, Roblox-native AI tools
- `open-cloud.md` — REST APIs, deploy, datastores, asset upload
- `ui.md` — React-lua, Fusion, layout primitives
- `assets-3d.md` — Blender pipeline, Cube/Mesh Gen, import
- `assets-audio.md` — ElevenLabs TTS, SFX, music pipeline
- `testing.md` — Jest-Lua, integration tests, CI
- `SKILL.md` — master routing doc (which reference to read for which task)
