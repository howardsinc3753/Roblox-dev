# Environment Setup

The filesystem-side stack for Roblox dev. Everything here lives outside Studio and is what makes Roblox projects diff-able, reviewable, and AI-friendly.

## The recommended baseline (2026)

For a fresh project on a new machine, install in this order:

1. **Roblox Studio** — `https://create.roblox.com/`. Free. The only program that opens `.rbxl`/`.rbxlx` files.
2. **Visual Studio Code** — the de facto editor for Luau in 2026. Sublime Text and Neovim work too with the same LSP.
3. **Rokit** (or Aftman) — toolchain manager. Pin Rojo, Wally, Lune, etc. per-project. Rokit is the spiritual successor to Aftman; Aftman is the spiritual successor to Foreman. Pick Rokit unless you have a reason not to. `https://github.com/rojo-rbx/rokit`
4. **Rojo** — installed via Rokit. The filesystem ↔ Studio bridge.
5. **Wally** — installed via Rokit. Package manager.
6. **Lune** — installed via Rokit. Standalone Luau runtime for build scripts, deploy scripts, and Open Cloud calls.
7. VSCode extensions: `evaera.vscode-rojo`, `JohnnyMorganz.luau-lsp`, `JohnnyMorganz.stylua`, `Kampfkarren.selene-vscode`.
8. **Roblox Studio plugins**: Rojo plugin (managed by the VSCode extension or installed manually). If using an MCP server, also that plugin.

Bash version, copy-pasteable:

```bash
# Install Rokit (macOS / Linux). Windows: see Rokit GitHub.
curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | sh

# In a new project
mkdir my-game && cd my-game
rokit init
rokit add rojo-rbx/rojo
rokit add UpliftGames/wally
rokit add lune-org/lune
rokit add JohnnyMorganz/StyLua
rokit add Kampfkarren/selene
rokit install

# Scaffold a Rojo project
rojo init
```

That gives you a `rokit.toml` (pinning versions), `wally.toml` (no deps yet), and a Rojo project structure with `src/` directories already mapped to ReplicatedStorage, ServerScriptService, and StarterPlayer.

## Rojo: the live-sync bridge

Rojo's job is two-way sync between filesystem files and instances inside Roblox Studio. **Live-sync goes filesystem → Studio.** Studio → filesystem requires building (`rojo build`) or using a third-party tool. This is the single most important thing to internalize.

### Project file (`default.project.json`)

This file maps folders/files on disk to a Roblox DataModel tree. A minimal example:

```json
{
  "name": "my-game",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "$className": "ReplicatedStorage",
      "Shared": { "$path": "src/shared" }
    },
    "ServerScriptService": {
      "$className": "ServerScriptService",
      "Server": { "$path": "src/server" }
    },
    "StarterPlayer": {
      "$className": "StarterPlayer",
      "StarterPlayerScripts": {
        "$className": "StarterPlayerScripts",
        "Client": { "$path": "src/client" }
      }
    }
  }
}
```

File extensions Rojo recognizes:
- `.luau` / `.lua` → ModuleScript (default)
- `.server.luau` → Script (server)
- `.client.luau` → LocalScript (client)
- `init.luau` inside a folder → that folder becomes a script with the init contents and children become its children
- `.meta.json` next to a file → adds properties (e.g. `{"properties": {"Disabled": true}}`)
- `.rbxmx` / `.rbxm` → embedded model (used for things you can't represent as code, like a styled Frame template)

### The two main commands

```bash
# Live-sync mode: starts a server on localhost:34872 that the Studio plugin connects to.
# Edits in src/ flow into Studio in real time.
rojo serve

# Build mode: produces a place file from the project, no Studio needed.
# Used in CI, or to bundle the game for upload via Open Cloud.
rojo build -o build/game.rbxl
rojo build -o build/game.rbxlx  # XML format, diffable
```

In Studio: open the Rojo plugin, click Connect. The plugin shows the diff before applying — useful when you sync into a place that has manual edits.

### When to use Rojo vs. raw Studio

Use Rojo as the source of truth for **all code**. Use raw Studio for things Rojo doesn't represent well: terrain, complex physics constraints, heavily-styled GUI templates, particle emitters, lighting and atmosphere settings. Sync those one-way (Studio → disk) by saving as `.rbxm` files via the Rojo plugin's "Save selection" or by checking in the entire `.rbxlx` periodically.

## Toolchain manager: Rokit (or Aftman)

The point of a toolchain manager is reproducibility. Without one, every dev on the team has whatever Rojo version they happened to install, and CI has whatever was current the last time someone updated the build image. With Rokit, every dev and every CI run uses the exact versions in `rokit.toml`.

```toml
# rokit.toml example
[tools]
rojo = "rojo-rbx/rojo@7.4.4"
wally = "UpliftGames/wally@0.3.2"
lune = "lune-org/lune@0.8.9"
stylua = "JohnnyMorganz/StyLua@0.20.0"
selene = "Kampfkarren/selene@0.27.1"
```

Run `rokit install` in any clone to materialize all tools at the pinned versions. CI: same one command.

Foreman still works but is unmaintained. If you inherit a Foreman project, migrate.

## Wally: package manager

Wally is to Roblox what Cargo is to Rust. Packages live at `https://wally.run/` and are scoped (`scope/name@version`).

Manifest:

```toml
# wally.toml
[package]
name = "myscope/my-game"
version = "0.1.0"
realm = "shared"  # "shared", "server", or "dev"
registry = "https://github.com/UpliftGames/wally-index"

[dependencies]
React = "jsdotlua/react@17.1.0"
ReactRoblox = "jsdotlua/react-roblox@17.1.0"
Promise = "evaera/promise@4.0.0"
Signal = "sleitnick/signal@1.5.0"

[dev-dependencies]
JestGlobals = "jsdotlua/jest-globals@3.10.0"
```

Then:

```bash
wally install
```

This creates a `Packages/` directory (and `ServerPackages/`, `DevPackages/` depending on realms) which Rojo's `default.project.json` should map into ReplicatedStorage. Standard project layout:

```
my-game/
├── default.project.json
├── wally.toml
├── wally.lock          # commit this
├── rokit.toml
├── src/
│   ├── shared/
│   ├── server/
│   └── client/
└── Packages/           # gitignored, generated
```

Common Wally packages worth knowing:
- `jsdotlua/react`, `jsdotlua/react-roblox` — the community-maintained React-lua fork
- `elttob/fusion` — Fusion UI framework
- `sleitnick/signal`, `sleitnick/knit`, `sleitnick/comm` — Sleitnick's framework suite
- `evaera/promise` — A+ Promises for Luau
- `roblox/roact` — legacy Roact (don't use for new work, but you'll see it in older codebases)
- `roblox-lua-promise/promise` — alternative promise lib

## Linting and formatting

- **StyLua**: opinionated formatter. `stylua src/`. Add a `stylua.toml` to override defaults (column width, quote style).
- **Selene**: linter. `selene src/`. Configure in `selene.toml` and `roblox.yml` (the latter declares Roblox globals like `game`, `workspace`, `task`, etc.).
- **luau-lsp**: language server. Real-time type checking, autocomplete, go-to-definition. Configure with `luaurc` files (`.luaurc` in project root, `--!strict` per-file pragma).

Pre-commit hook recommendation: run `stylua --check` and `selene src/`. Both are fast.

## Standalone Luau runtimes: Lune and Lute

These are not for running your game — they're for **build scripts, deploy scripts, codegen, and Open Cloud calls**. Both let you write Luau outside Roblox.

**Lune** (`https://github.com/lune-org/lune`):
- Battle-tested, widely used in 2025–2026 Roblox CI pipelines
- Includes a `roblox` standard library that can read/write `.rbxl`/`.rbxm` files and manipulate instance trees offline
- Built-in HTTP, filesystem, process, stdio APIs
- Familiar to Roblox devs (1:1 task scheduler port)

```luau
-- deploy.luau — example Lune script
local net = require("@lune/net")
local process = require("@lune/process")

local apiKey = process.env.ROBLOX_API_KEY
local response = net.request({
    url = "https://apis.roblox.com/cloud/v2/universes/123456/places/789",
    method = "PATCH",
    headers = {
        ["x-api-key"] = apiKey,
        ["Content-Type"] = "application/octet-stream",
    },
    body = require("@lune/fs").readFile("build/game.rbxl"),
})

print("Deploy:", response.statusCode)
```

Run with `lune run deploy.luau`.

**Lute** (`https://lute.luau.org/`) is newer and more general-purpose ("Node.js for Luau"). Bundled test runner, linter, type checker. Use Lute if you want a fully Luau-native dev environment for non-Roblox tooling. Use Lune if you specifically need the `roblox` library for working with place files.

## roblox-ts (TypeScript alternative)

If you'd rather write TypeScript that compiles to Luau: `https://roblox-ts.com/`. Maintained ecosystem with its own packages (`@rbxts/*` on npm). Good fit for teams already proficient in TypeScript. Trade-off: smaller community than Luau-native, occasional compiler bugs around edge-case Luau features, and your AI agent has to know it's emitting TS not Luau.

```bash
npm init roblox-ts
npm run build       # compiles src/ → out/ (Luau)
npm run watch       # live recompile
```

Combine with Rojo by pointing the project file at `out/` instead of `src/`.

## Recommended folder layout for a Claude-Code-driven project

```
my-game/
├── README.md
├── DESIGN.md             # the game design doc — Claude Code reads this on every session
├── rokit.toml
├── wally.toml
├── wally.lock
├── default.project.json
├── stylua.toml
├── selene.toml
├── roblox.yml
├── .luaurc
├── .gitignore            # Packages/, build/, .vscode/local
├── src/
│   ├── shared/           # ReplicatedStorage — runs on both
│   │   ├── Modules/
│   │   └── Network/
│   ├── server/           # ServerScriptService
│   └── client/           # StarterPlayerScripts
├── tests/                # Jest-Lua specs
├── scripts/              # Lune scripts: deploy, datastore migrate, asset upload
└── build/                # gitignored, output of `rojo build`
```

This layout gives Claude Code a stable surface: `DESIGN.md` for intent, `src/` for code, `scripts/` for ops, `tests/` for verification.

## Common gotchas

- **Rojo plugin version must match Rojo CLI major version.** v7 plugin can't talk to v6 CLI.
- **The `Packages/` folder must be re-mapped in `default.project.json`** (typically into ReplicatedStorage). Wally doesn't do this for you.
- **Don't commit `Packages/`** — it's regenerated from `wally.lock`. Do commit `wally.lock`.
- **`rojo serve` only handles code, not assets.** Models, textures, audio are uploaded separately (Studio asset manager, or Open Cloud Assets API).
- **`game.HttpService:RequestAsync` is disabled by default** in published places. Enable it in Game Settings → Security → Allow HTTP Requests.
- **In Studio, `task.wait()` not `wait()`.** The older `wait` global is throttled and deprecated.

## Where to read more

- Rojo: `https://rojo.space/docs/v7/`
- Wally: `https://wally.run/`
- Rokit: `https://github.com/rojo-rbx/rokit`
- Lune: `https://lune-org.github.io/docs/`
- Lute: `https://lute.luau.org/`
- Luau: `https://luau.org/`
- roblox-ts: `https://roblox-ts.com/`
- Selene: `https://kampfkarren.github.io/selene/`
- StyLua: `https://github.com/JohnnyMorganz/StyLua`
