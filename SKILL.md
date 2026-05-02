---
name: roblox-dev-sdk
description: Kickstart Roblox game development end-to-end — scripting in Luau or roblox-ts, syncing code with Rojo, managing packages with Wally, calling Open Cloud APIs, driving Roblox Studio via MCP, generating 3D assets with Cube/Mesh Generation, building UI with React-lua or Fusion, and pulling in voiceover from ElevenLabs. Use this skill whenever the user mentions Roblox, Luau, Roblox Studio, Rojo, Open Cloud, an .rbxl/.rbxlx/.rbxm file, building a Roblox experience, or wants to design, code, automate, deploy, or generate assets for a Roblox game — even if they don't say "Roblox skill" explicitly.
---

# Roblox Dev SDK Corpus

This skill is the orientation map for building Roblox games with Claude Code. It exists because Roblox dev is a constellation of independent tools (Studio, Rojo, Wally, Lune, Open Cloud, MCP servers, AI generators, external pipelines like Blender and ElevenLabs) and the right move depends on what the user is actually trying to do. This file picks the path; the `references/` files have the depth.

## Pick the right reference

Read only the references that match the task. Each is self-contained.

| Task | Read |
|---|---|
| First-time setup, picking an editor, syncing code, package management | `references/environment.md` |
| Writing scripts (Luau, types, roblox-ts, formatting/linting) | `references/languages.md` |
| Driving Studio from Claude Code via MCP, using Roblox's built-in AI (Cube, Mesh Gen, Code Assist, Assistant) | `references/ai-and-mcp.md` |
| Server-side automation, datastores, asset upload, deployment from CI | `references/open-cloud.md` |
| Building HUDs, menus, in-game UI | `references/ui.md` |
| 3D models, textures, animations, importing from Blender, AI-generated meshes | `references/assets-3d.md` |
| NPC voices, music, SFX — including ElevenLabs → Roblox pipeline | `references/assets-audio.md` |
| Unit tests, integration tests, automated playtesting | `references/testing.md` |

## The 60-second mental model

Roblox dev splits cleanly into **three planes**:

1. **The runtime** (Roblox Studio + the live game servers). Code runs as Luau. Studio is the canonical editor and the only place a place file (`.rbxl`/`.rbxlx`) actually opens. Studio also hosts the playtest, the explorer tree, and all asset import dialogs.
2. **The filesystem project** (your git repo). Source of truth for serious projects. Lives as `.luau`/`.lua` files plus a `default.project.json` that maps folders to Roblox instance paths. **Rojo** is the bridge between this and Studio — it live-syncs filesystem edits into a running Studio session.
3. **The cloud** (roblox.com APIs). **Open Cloud** is the official REST surface for everything outside the engine: upload assets, read/write datastores, message live servers, deploy place updates, manage products and gamepasses.

Most "real" projects live on plane 2 (filesystem + git) and use Rojo to push to plane 1 (Studio) for testing, then Open Cloud (plane 3) for CI/CD and production data ops.

## The Claude Code workflow that actually works

This pattern emerged from creators shipping production games with Claude Code in 2025–2026:

1. **Write a design doc first.** A markdown file describing mechanics, data structures, progression, monetization. AI agents have no game-design intuition — the doc is the shared brain. ~100–200 lines is normal.
2. **Install the Studio MCP server.** Connect Claude Code to a live Studio session so it can create instances, edit scripts, run code, and read console output directly. See `references/ai-and-mcp.md` — the recommended option in 2026 is `boshyxd/robloxstudio-mcp` (43+ tools, npx install) or the official `Roblox/studio-rust-mcp-server`.
3. **Set up Rojo so the AI works on files, not just instances.** Even with MCP, having a `src/` directory on disk gives Claude Code a stable workspace it can grep, refactor, and version-control. Use `rojo init` to scaffold.
4. **Let Claude handle pure logic; you handle visuals.** The split is consistent: server scripts, modules, data structures, RemoteEvent wiring, leaderstats, datastore code → AI. 3D placement, lighting, materials, particles, animation tuning → human in Studio (or use the AI generators, which are Studio plugins, not external tools). This split saves hours of frustrating "I can't see what it looks like" loops.
5. **Use Open Cloud for anything that has to happen outside Studio** — uploading generated audio, scheduled datastore migrations, publishing places from CI, sending in-game messages from a Discord bot.

## Tool inventory at a glance

The user mentioned wanting all their tools laid out. Here's the full set this corpus covers:

**Core engine & language**
- Roblox Studio (the editor, playtest host, plugin surface)
- Luau (the language; gradually-typed Lua 5.1 fork) + `luau-analyze` (type checker/linter)
- roblox-ts (TypeScript → Luau compiler; optional alternative)

**Filesystem-side tools**
- Rojo (filesystem ↔ Studio sync)
- Aftman / Rokit (toolchain managers — pin tool versions per project)
- Wally (package manager, Cargo-style)
- Lune (standalone Luau runtime for build scripts, CI, Open Cloud automation)
- Lute (newer general-purpose Luau runtime; alternative to Lune)
- Selene + StyLua (linter + formatter)
- luau-lsp (LSP for VSCode/Neovim/Sublime)

**AI integration (Claude Code side)**
- `Roblox/studio-rust-mcp-server` (official MCP server)
- `boshyxd/robloxstudio-mcp` (community MCP server, 43+ tools, easiest install)
- `weppy/roblox-mcp` (alternative with bidirectional sync, playtest control)

**AI integration (Roblox-native, in Studio)**
- Roblox Assistant (in-Studio agent with Planning Mode, playtest agent — 2026)
- Code Assist (inline Luau autocomplete)
- Cube 3D / Mesh Generation API (text → 3D mesh)
- Procedural Models (parametric 3D primitives, 2026 beta)
- Material Generator (text → tileable PBR)
- Texture Generator (text → asset-mapped textures)
- Avatar Auto-Setup (mesh → rigged R15)

**Cloud surface**
- Open Cloud APIs: Datastores, Messaging, Assets, Place Publishing, Universes, Developer Products, Game Passes, Groups, OAuth2, in-experience HttpService access to Open Cloud (no proxy needed since 2025)

**UI**
- React-lua (Roblox-maintained React port; recommended for new work)
- Fusion (state-driven, scope-based; popular alternative)
- Roact (deprecated — don't start new projects with it)
- UI Labs / Storybook for Roblox

**External asset pipelines**
- Blender (with the official Roblox Blender Plugin) → FBX/OBJ/glTF
- Tripo3D, Meshy, Luma — image/text → 3D for Roblox import
- ElevenLabs (TTS → MP3 → Open Cloud Asset upload → in-game AudioId)
- Figma → image export → Roblox decals/UI textures

**Testing**
- Jest-Lua (Roblox port of Jest; recommended)
- TestEZ (older but widely used)
- Studio's playtest agent (2026) — Assistant runs the game and verifies behavior against the plan

## When the user asks for X, do Y

These are common starting prompts and the right opening move:

- *"Help me build a [genre] game"* → Don't start coding. Ask for the design doc or offer to draft one. Then read `references/environment.md` to scaffold the project, then `references/ai-and-mcp.md` to get the MCP bridge running.
- *"Connect Claude Code to my Studio"* → `references/ai-and-mcp.md`, "MCP server setup" section.
- *"Upload this audio/image/model to my game"* → `references/open-cloud.md`, Assets API.
- *"Give my NPC a voice"* → `references/assets-audio.md` — ElevenLabs TTS, then Open Cloud asset upload, then reference the resulting `rbxassetid://` in a Sound instance.
- *"Make a shop UI"* → `references/ui.md` — start with React-lua unless they have a Fusion preference.
- *"Make a [thing] mesh"* → `references/assets-3d.md` — choose between in-Studio Mesh Generation (fastest) and Blender (most control).
- *"Deploy my place from GitHub Actions"* → `references/open-cloud.md`, Place Publishing + API key setup.
- *"Migrate datastores"* → `references/open-cloud.md` + Lune script (fastest CI-friendly path).

## Hard truths to surface early

Be honest with the user about what doesn't work:

- **AI agents are bad at things requiring visual judgment.** Color, lighting, particle tuning, "does this feel good" — these need human eyes. Don't promise to get them right via MCP.
- **MCP can't see Studio's viewport.** It can read the explorer tree and console output, not pixels. If a bug is visual ("blocks turned white after respawn"), Claude Code can't catch it without you running the playtest.
- **Free-tier Open Cloud has rate limits** — datastore writes, asset uploads, and message publishes all have per-minute caps. Plan around them for any bulk operation.
- **Generative 3D output still needs cleanup.** Cube/Mesh Generation outputs MeshParts that often need scale, pivot, or material adjustment before they look right. Don't ship raw output to a polished game.
- **ElevenLabs audio is uploaded, not streamed.** Roblox doesn't run external WebSockets in-game for live TTS. Generate offline, upload as an asset, play the AssetId.
- **Roblox tooling rot is real.** Roact is deprecated, Foreman is being replaced by Aftman/Rokit, Cube 3D APIs are moving from beta. Always check current docs before committing to a tool.

## Where to find the canonical docs

- Roblox Creator Docs: `https://create.roblox.com/docs`
- Open Cloud reference: `https://create.roblox.com/docs/cloud`
- Luau language: `https://luau.org/`
- Rojo: `https://rojo.space/docs/`
- Wally: `https://wally.run/`
- React-lua "How To" (official): search Roblox DevForum for "How To: React + Roblox"
- Fusion: `https://elttob.uk/Fusion/`
- ElevenLabs API: `https://elevenlabs.io/docs/api-reference`
