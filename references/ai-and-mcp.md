# AI and MCP

Two distinct AI surfaces: **MCP servers** that connect Claude Code to a live Roblox Studio session (external AI driving Studio), and **Roblox-native AI tools** that run inside Studio (Roblox's own models). They're complementary — Claude Code via MCP for code and architecture, Roblox-native AI for asset generation and quick visuals.

## MCP servers — connecting Claude Code to Studio

The Model Context Protocol bridges Claude Code (your terminal) and Roblox Studio (the editor). Without it, Claude Code can only generate code that you copy into Studio. With it, Claude Code can directly create instances, edit scripts, run Luau, read console output, start playtests, and modify the data model.

Three options as of 2026, ordered by how easy they are to install:

### 1. `boshyxd/robloxstudio-mcp` (recommended starting point)

`https://github.com/boshyxd/robloxstudio-mcp`. ~43+ tools. One-line install via npx. This is the package that the "I built a Roblox game using only AI agents" Medium post used (Apr 2026), and it's the most painless option.

```bash
# Add to Claude Code
claude mcp add robloxstudio -- npx -y robloxstudio-mcp@latest

# Download the matching Studio plugin
curl -L "https://github.com/boshyxd/robloxstudio-mcp/releases/latest/download/MCPPlugin.rbxmx" \
  -o ~/Documents/Roblox/Plugins/MCPPlugin.rbxmx
# (On Windows: %LOCALAPPDATA%\Roblox\Plugins\)
```

Then in Studio: enable Allow HTTP Requests in Game Settings → Security. Open the plugin — it should show "Connected".

There's also an inspector-only variant `robloxstudio-mcp-inspector` that's read-only — useful for safely browsing structure or reviewing code without write access.

### 2. `Roblox/studio-rust-mcp-server` (the official one)

`https://github.com/Roblox/studio-rust-mcp-server`. First-party. Requires building from Rust source (no npm publish).

Tools exposed:
- `run_code` — execute Luau in Studio, return printed output
- `insert_model` — insert a model from the Creator Store
- `get_console_output` — read console
- `start_stop_play` — start/stop playtest
- `run_script_in_play_mode` — run a script in playtest, capture logs/errors/duration

```bash
git clone https://github.com/Roblox/studio-rust-mcp-server.git
cd studio-rust-mcp-server
cargo build --release
# Then build the plugin:
cd plugin && rojo build --output MCPStudioPlugin.rbxmx
# Install plugin into Studio's Plugins folder, then:
claude mcp add --transport stdio Roblox_Studio -- \
  /path/to/target/release/rbx-studio-mcp --stdio
```

Smaller surface area than boshyxd but more stable, more carefully reviewed, and gets first access to new official Studio capabilities (Roblox is shipping more MCP tooling on this server in 2026).

### 3. `weppy/roblox-mcp` (action-based, has a Pro tier)

`https://github.com/hope1026/weppy-roblox-mcp`. Action-based dispatching (one tool with action verbs vs. dozens of separate tools). Bidirectional sync, automated playtest control, web dashboard, multi-place support. Free tier covers basic execution; Pro adds bulk ops, terrain generation, audio/animation control.

```bash
claude mcp add weppy -- npx -y @weppy/roblox-mcp
```

Worth knowing about, especially if you want the playtest agent loop ("start a playtest, verify the NPC reaches the target, report back").

### Choosing

- **Default**: boshyxd. Easiest setup, broadest tool coverage, npx-installable.
- **Want first-party stability**: official Roblox server.
- **Want playtest automation and bidirectional sync**: weppy (consider Pro).

You can run multiple. They don't conflict; Claude Code sees them as separate tool namespaces.

### 4. `@meshy-ai/meshy-mcp-server` (3D asset generation)

`https://www.meshy.ai/`. Not a Studio bridge — this connects Claude Code to Meshy's AI 3D generation API. Complementary to the Studio MCP servers above: Studio MCP drives the editor, Meshy MCP generates the assets.

```bash
# Already configured in .mcp.json for this project
npx -y @meshy-ai/meshy-mcp-server@latest
# Requires MESHY_API_KEY env var
```

Tools: `meshy_text_to_3d`, `meshy_image_to_3d`, `meshy_text_to_3d_refine`, `meshy_remesh`. See `references/assets-3d.md` for the full Meshy → Roblox pipeline.

### What MCP can and can't do

**Can:**
- Create / delete / rename / reparent instances
- Write and edit Scripts and ModuleScripts
- Run Luau code with arbitrary side effects (set properties, generate parts, call services)
- Read the console (print/warn/error output)
- Start and stop playtests, run scripts during playtest
- Insert models from the Creator Store

**Can't:**
- See the viewport. MCP doesn't ship pixels back. If a bug is "the cube turned white" or "the lighting feels wrong", Claude Code is blind. You have to look.
- Edit terrain heightmaps directly (some servers expose terrain APIs but the surface is limited).
- Interact with Studio's modal dialogs (asset upload, publish flow, etc.).
- Persist across Studio restarts unless you also use Rojo to keep code on disk.

### The recommended workflow

Even with MCP, **also use Rojo**. Reasons:

1. The MCP plugin only shows changes in the live Studio session. If Studio crashes mid-edit, your code can be lost. Rojo on disk = git history = safe.
2. Claude Code can grep, search, and refactor across files much faster than via MCP tool calls.
3. CI/CD only ever sees the filesystem.

So the loop is: edit on disk → Rojo syncs to Studio → MCP runs/tests → MCP reports back → repeat. Use MCP for runtime verification (run this code, what's the output?) more than for source editing.

---

## Roblox-native AI tools (inside Studio)

These are built into Studio and run on Roblox's models. Different surface from external MCP — you typically invoke them through the Assistant panel or right-click context menus, not from Claude Code.

### Roblox Assistant (2026: agentic)

The in-Studio AI panel. As of 2026 it has:

- **Planning Mode** — multi-step collaborative agent. Asks clarifying questions, builds a task manifest, executes against it, checks work against the original plan. Will auto-store context across sessions soon.
- **Playtesting agent (beta)** — tests the game against the plan, reads logs, uses the player character as automated QA.
- **MCP client** — Studio itself can act as an MCP client, connecting outward to external tools (Claude, Cursor, Codex). This is the inverse direction from the MCP servers above and is rolling out through 2026.

Per Roblox's own data: 44% of the top 1,000 creators use Assistant or third-party AI via MCP. 50%+ of Studio sessions from creators who joined in 2024–2025 used at least one AI feature.

### Code Assist

Inline Luau autocomplete. Suggestions appear as you type. ~535M characters of code accepted as of June 2024, much more by 2026. Best for boilerplate (datastore setup, RemoteEvent wiring, leaderstats). Less reliable for game architecture and occasionally suggests deprecated APIs from training data.

### Cube 3D / Mesh Generation API

`/generate a motorcycle` in the Assistant prompt → textured 3D mesh in seconds. Powered by Roblox's Cube foundation model (1.8B params, trained on 1.5M assets, open-sourced March 2025). 

Use it for:
- Placeholder props (massive time-saver in early prototyping)
- Generic furniture, vehicles, foliage, decoration

Don't expect:
- Hero assets (the centerpiece sword, the main character) — quality is good for placeholders, not for shipping
- Complex articulated meshes
- Specific stylistic match — Cube has a "look" that's improving but not yet character-art-director-tier

### Procedural Models (2026 beta)

Parametric 3D models defined by code or AI. Adjust attributes (number of bookshelf shelves, staircase height, building floors) and the geometry regenerates. Great for buildings, furniture, modular environments. Combine with Cube for hybrid: AI generates a base, you parametrize variants.

Enable: Studio Beta → "Edit-Time Procedural Models".

### Material Generator

Text → tileable PBR materials (diffuse + normal + roughness). Inside Studio, MaterialService → Generate. Roblox reports >100% increase in PBR material variations among users (March 2023 baseline → June 2024).

### Texture Generator

Text → asset-specific textures mapped to a target mesh. Different from Material Generator (tileable surfaces) — this projects a texture onto a specific UV layout.

### Avatar Auto-Setup

Mesh → rigged R15 avatar. Predicts joint positions, generates cage meshes for layered clothing. Roblox's surveys: 60–70% time savings on standard humanoids. Quality drops sharply on quadrupeds, fantasy creatures, or stylized proportions — manual review required before upload.

### NPC dialogue (limited beta moving to broader rollout)

Roblox-hosted LLM with content moderation, configured per-NPC. Lets you ship NPCs that respond to player chat without running your own LLM infra. Good for ambient flavor characters; not yet a replacement for scripted critical-path dialogue.

---

## When to use which AI surface

| Need | Use |
|---|---|
| Generate/edit code, architecture decisions, refactors | Claude Code via MCP |
| Run scripts and verify behavior in a live session | Claude Code via MCP (`run_code`, `run_script_in_play_mode`) |
| Quick placeholder mesh | Cube / Mesh Gen in Studio Assistant |
| Tileable wall/floor texture | Material Generator in Studio |
| Rig an uploaded humanoid mesh | Avatar Auto-Setup in Studio |
| Iterate on a multi-step build with planning + verification | Studio Assistant (Planning Mode) **or** Claude Code with MCP playtest tool |
| Inline autocomplete while typing | Code Assist (Studio's native; works alongside Claude Code) |
| Ambient NPC chat | Roblox NPC dialogue beta |

You can and should mix. A productive 2026 setup: Claude Code with MCP for everything code-side, Studio Assistant for Mesh Generation and Material Generator (these aren't exposed via MCP yet), Code Assist on for inline suggestions when you're typing in Studio directly.

---

## Hard truths from real shipped projects

From the April 2026 Medium post "I Built a Roblox Game Using Only AI Agents" (built a mining/rebirth game with Claude Code + boshyxd MCP):

- **Claude is excellent at server scripts, data structures, client input handling, RemoteEvent wiring.** First-pass-correct most of the time on standard patterns.
- **Claude is bad at anything visual.** Lighting, particle tuning, "does this color feel good", placement of decoration. The author lost 45 minutes diagnosing a "blocks turned white" bug because MCP can't see the viewport.
- **Net time savings for a logic-heavy game**: ~40-50% over building solo. AI saves time on scripts, adds friction on visuals.
- **The design doc is essential.** ~130 lines of markdown design + ~970 lines of implementation plan with specific MCP tool calls per phase, six phases, 25 tasks. Without this scaffolding, agents wander.

The clean rule: **AI does the logic, human does the visuals.** Plan accordingly.

---

## Reading list

- Official Roblox MCP server: `https://github.com/Roblox/studio-rust-mcp-server`
- boshyxd MCP: `https://github.com/boshyxd/robloxstudio-mcp`
- weppy MCP: `https://github.com/hope1026/weppy-roblox-mcp`
- Roblox AI announcements: search "Studio MCP Server Updates" and "Roblox Studio is Going Agentic" on the DevForum
- Cube 3D blog post: `https://about.roblox.com/newsroom/2025/03/introducing-roblox-cube`
- Studio Beta posts on DevForum (Procedural Models, Cube 3D Generation Tools)
