# Languages: Luau (and roblox-ts)

Roblox runs **Luau**, a fork of Lua 5.1 maintained by Roblox and now used outside Roblox too (Alan Wake 2, Farming Sim 2025, Second Life, Warframe). For a Claude-Code-assisted workflow, write Luau directly unless you have a reason to use roblox-ts.

## Luau in 30 seconds

Looks like Lua 5.1, with these additions worth knowing immediately:

- **Gradual type system.** `local x: number = 5`. Inference is good; explicit annotations are mainly for function signatures and module exports. Three modes: `--!nocheck`, `--!nonstrict` (default), `--!strict`.
- **Generalized iteration.** `for i, v in array do` — no more `pairs`/`ipairs` for most cases.
- **`continue`** keyword (Lua 5.1 didn't have it).
- **`+=`, `-=`, `*=`, `/=`, `//=`, `%=`, `^=`, `..=`** compound assignment.
- **String interpolation.** `` `Hello ${name}` `` — backticks, dollar-brace.
- **`if`/`elseif` expressions.** `local x = if cond then a else b`.
- **Type aliases, type intersections, generics, optional types.** `type Maybe<T> = T?`. `type Both = A & B`.
- **`safe navigation`** is *not* in Luau yet (no `?.`). Use `if x then x.y else nil` patterns.

## Roblox-specific globals (the ones Claude Code should reach for first)

- `game` — root DataModel. `game:GetService("Players")`, `game:GetService("ReplicatedStorage")`, etc.
- `workspace` — shortcut for `game.Workspace`.
- `script` — the current script's instance (use `script.Parent` for sibling lookup).
- `task` — modern scheduler. `task.wait(n)`, `task.spawn(fn)`, `task.defer(fn)`, `task.delay(n, fn)`. Replaces the older `wait`, `spawn`, `delay` which are throttled.
- `typeof` — like `type` but knows Roblox types (`"Instance"`, `"Vector3"`, `"CFrame"`, etc.).
- `require` — module loader. `require(script.Parent.MyModule)`.

Common services to know: `Players`, `ReplicatedStorage`, `ServerScriptService`, `RunService`, `UserInputService`, `TweenService`, `HttpService`, `DataStoreService`, `MessagingService`, `Lighting`, `SoundService`, `MarketplaceService`, `BadgeService`, `TextChatService`, `ChatService` (legacy).

Always cache services at the top of files: `local Players = game:GetService("Players")`. Don't index `game.Players` inline — it's slower and triggers a deprecation lint.

## Module patterns

Every non-trivial file should be a ModuleScript. The canonical shape:

```luau
-- src/shared/Modules/Inventory.luau
local Inventory = {}
Inventory.__index = Inventory

export type Inventory = typeof(setmetatable(
    {} :: { items: { [string]: number }, capacity: number },
    Inventory
))

function Inventory.new(capacity: number): Inventory
    local self = setmetatable({}, Inventory)
    self.items = {}
    self.capacity = capacity
    return self
end

function Inventory.add(self: Inventory, itemId: string, count: number): boolean
    self.items[itemId] = (self.items[itemId] or 0) + count
    return true
end

return Inventory
```

The `export type` line lets other modules `local Inventory = require(...)` and use `Inventory.Inventory` as a type annotation. This is the idiomatic way to make Luau modules properly typed.

## Server / client / shared split

Three places code can live, with different replication and visibility:

- **`ServerScriptService`** — server-only Scripts. Authority lives here. Money, inventory mutations, ban logic, datastore writes.
- **`StarterPlayerScripts` / `StarterPlayerCharacterScripts`** — client-only LocalScripts. Input, camera, UI, prediction. Cloned to each player when they spawn.
- **`ReplicatedStorage`** — modules that both sides need (e.g., a shared Inventory class definition). ModuleScripts here are sandboxed: server-side `require` runs server context, client-side `require` runs client context. Don't put secrets here — clients can read it.
- **`ServerStorage`** — server-only modules (server-only NPC AI, secret data tables).

**Network boundary**: cross with `RemoteEvent` (fire-and-forget) and `RemoteFunction` (request/response). Validate every payload server-side. The client is hostile by default — exploiters can call any RemoteEvent with any args.

```luau
-- src/shared/Network/Remotes.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
return {
    PurchaseItem = Remotes:WaitForChild("PurchaseItem") :: RemoteEvent,
    GetInventory = Remotes:WaitForChild("GetInventory") :: RemoteFunction,
}
```

For larger projects, use a networking library (Sleitnick's `Comm`, or `ByteNet`, or roblox-ts's `@rbxts/net`) to get type-safe RPC.

## Type checking modes

Top of every file you care about:

```luau
--!strict
```

In strict mode, the type checker errors on type mismatches instead of warning. Pair with `luau-analyze src/` in CI to catch regressions. The transition strategy on existing codebases: leave files in `--!nonstrict` (default) and migrate hot paths file-by-file.

`.luaurc` in the project root configures defaults:

```json
{
    "languageMode": "strict",
    "lintErrors": true,
    "typeErrors": true,
    "globals": ["MyGlobalThing"]
}
```

## Common Luau idioms Claude Code should default to

**Service caching:**
```luau
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
```

**Safe waits with timeout:**
```luau
local part = workspace:WaitForChild("Part", 5)
if not part then warn("Part never appeared") return end
```

**Heartbeat loops instead of `while wait()`:**
```luau
RunService.Heartbeat:Connect(function(dt)
    -- runs every frame
end)
```

**Pcall everything that can yield or fail:**
```luau
local ok, result = pcall(function()
    return DataStore:GetAsync(key)
end)
if not ok then
    warn("Datastore read failed:", result)
    return
end
```

**Connections are leaks waiting to happen.** Always store the `RBXScriptConnection` and `:Disconnect()` it when the owning object dies. For non-trivial cleanup, use a Maid/Trove pattern (Sleitnick's `Trove` is the standard).

```luau
local Trove = require(ReplicatedStorage.Packages.Trove)
local trove = Trove.new()
trove:Connect(part.Touched, onTouch)
trove:Add(someInstance)
-- later:
trove:Destroy()  -- disconnects and destroys everything
```

## Anti-patterns to call out

- **`while wait() do`** — use `task.wait()` and prefer event-driven code.
- **`spawn(fn)`** — use `task.spawn(fn)`. Old `spawn` has a throttling delay.
- **Unbounded `RemoteEvent` from the client.** Always rate-limit or sanity-check.
- **Storing references in `_G`.** Use ReplicatedStorage modules.
- **`game.Workspace.Part`** dotted access — use `:WaitForChild` or `:FindFirstChild` because instances aren't guaranteed to exist on the client when scripts start.
- **Heavy work in `RenderStepped`** — anything other than camera/character updates should run on `Heartbeat` or be event-triggered.

## roblox-ts (TypeScript alternative)

`https://roblox-ts.com/`. Compiles TypeScript to Luau. Strong typing, npm ecosystem (`@rbxts/*` packages). Good fit if your team is already TS-fluent and you don't mind a compile step.

Setup:
```bash
npm init roblox-ts
npm install              # installs @rbxts/types, etc.
npm run build            # one-shot compile
npm run watch            # live recompile
```

Key `@rbxts` packages: `@rbxts/services`, `@rbxts/net`, `@rbxts/react`, `@rbxts/react-roblox`, `@rbxts/promise`, `@rbxts/signal`.

When working on a roblox-ts project, point Rojo at the `out/` directory (the compiler's output), not `src/`. The Rojo config typically lives at `default.project.json` and references `out/shared`, `out/server`, etc.

**Trade-offs:** much smaller package ecosystem than Wally + native Luau. Compiler bugs are rare but real. Type errors blocking builds is great for safety, painful when you just want to test. Most Roblox tutorials and DevForum answers are in Luau, so you have a translation tax. Pick it deliberately, not by default.

## Reading list

- Luau site: `https://luau.org/`
- Roblox Creator Docs Luau section: `https://create.roblox.com/docs/luau`
- Sleitnick's tutorials (high-quality, idiomatic): `https://sleitnick.github.io/RbxBook/`
- roblox-ts: `https://roblox-ts.com/docs/`
