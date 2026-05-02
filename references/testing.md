# Testing

Three layers, in increasing order of fidelity:

1. **Unit tests** — pure logic in modules, no Roblox runtime needed. Run from CLI in seconds. Use **Jest-Lua** (preferred) or TestEZ.
2. **Integration tests in Studio** — code that depends on Roblox services (Players, RunService, datastores). Run inside Studio with a test runner.
3. **Automated playtests** — full game launches with a bot or AI agent verifying behavior. Use **Studio Assistant's playtest agent** (2026) or weppy MCP's playtest tools.

You don't need all three on day one. Start with unit tests for any module that has actual logic (combat math, inventory, progression formulas). Add integration tests when you find yourself manually testing the same flow repeatedly. Add playtest agents only for late-stage QA.

## Unit testing with Jest-Lua

`https://github.com/jsdotlua/jest-lua`. Roblox port of Jest. Familiar to anyone who's used the JS version. The community-maintained fork is current; the original Roblox internal version is what powers their CI.

### Setup via Wally

```toml
[dev-dependencies]
JestGlobals = "jsdotlua/jest-globals@3.10.0"
Jest = "jsdotlua/jest@3.10.0"
```

`wally install`. Add a Rojo project file or use Lune to run.

### A test file

```luau
-- tests/Inventory.spec.luau
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, test, expect, beforeEach = JestGlobals.describe, JestGlobals.test, JestGlobals.expect, JestGlobals.beforeEach

local Inventory = require(ReplicatedStorage.Shared.Modules.Inventory)

describe("Inventory", function()
    local inv

    beforeEach(function()
        inv = Inventory.new(10)
    end)

    test("starts empty", function()
        expect(inv.items).toEqual({})
    end)

    test("add inserts items", function()
        inv:add("sword", 1)
        expect(inv.items.sword).toBe(1)
    end)

    test("add stacks identical items", function()
        inv:add("apple", 3)
        inv:add("apple", 2)
        expect(inv.items.apple).toBe(5)
    end)
end)
```

### Running tests

Two options:

**Option A: Run inside Studio.** Run a `RunTests.server.luau` once, which uses `runCLI` to execute all `.spec.luau` files under a folder, prints results to the output console. Fine for local dev, no good for CI.

**Option B: Run via Lune (recommended for CI).** Lune can require Roblox modules outside Studio if they don't depend on engine-only services. For modules that do, use `Roblox.runCli` patterns or stub the services. The jsdotlua Jest fork has Lune compatibility patterns documented.

### Mocking Roblox services

For modules that depend on `game:GetService(...)`, inject the dependency rather than calling `GetService` inline:

```luau
-- Bad (hard to test)
local function getOnlinePlayers()
    return #game:GetService("Players"):GetPlayers()
end

-- Good (testable)
local function getOnlinePlayers(playersService)
    return #playersService:GetPlayers()
end
```

In tests, pass a mock object with the methods you need.

## TestEZ (legacy but still common)

`https://github.com/Roblox/testez`. Original Roblox testing framework. BDD-style (`describe`/`it`). Less feature-rich than Jest-Lua but very lightweight. Many older codebases use it. New projects: prefer Jest-Lua.

```toml
[dev-dependencies]
TestEZ = "roblox/testez@0.4.1"
```

```luau
return function()
    describe("Inventory", function()
        it("starts empty", function()
            local inv = Inventory.new(10)
            expect(#inv.items).to.equal(0)
        end)
    end)
end
```

If you're inheriting a TestEZ codebase, don't migrate just to migrate. The matchers are different but the logic is portable when you do migrate.

## Integration tests in Studio

For things that need a real Roblox runtime — RunService loops, Players events, DataStore access (against Studio's mock datastore), networking — write tests as scripts placed somewhere like `ServerScriptService.Tests` and run them on game start.

Pattern:

```luau
-- src/server/Tests/init.server.luau
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end  -- never run in production

local TestRunner = require(script.TestRunner)
TestRunner:RunAll()
```

Studio-only tests catch a class of bugs unit tests can't (signal timing, RemoteEvent latency, replication), at the cost of slower iteration.

## Automated playtesting

The 2026 capabilities here are new and rapidly improving:

### Studio Assistant's playtest agent (beta)

Roblox-native. Assistant runs the game in playtest mode, uses the player character as a QA tester, reads logs, compares behavior against the original plan, and surfaces problems. Great for "did the game stay playable after this change?" smoke checks.

Available in Studio's Assistant panel. Beta as of April 2026; rollout continuing.

### MCP-driven playtests

The weppy and Roblox official MCP servers expose `start_stop_play` and `run_script_in_play_mode`. This lets Claude Code:

1. Start a playtest.
2. Inject a test script (move the character to a checkpoint, fire a RemoteEvent, check inventory).
3. Read the console output for assertions.
4. Stop the playtest.
5. Report results.

Example prompt to Claude Code: *"Start a playtest, walk the character to the shop NPC, fire the PurchaseItem remote with item ID 'sword', verify the inventory updated, stop the playtest, summarize what happened."*

This kind of end-to-end check catches things that unit tests can't (replication delays, race conditions, UI state).

## Type checking is testing too

`luau-analyze --mode=strict src/` in CI catches a huge class of bugs that would otherwise be runtime errors. Treat it as a required test step.

```bash
# In your CI:
rokit install
luau-analyze --mode=strict src/
```

Tighten the screw over time: start in `--!nonstrict`, migrate one module at a time to `--!strict`, eventually flip the project default in `.luaurc`.

## Recommended CI stack

A solid CI workflow for a Roblox project:

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ok-nick/setup-aftman@v0
      - run: aftman install
      - run: stylua --check src/ tests/
      - run: selene src/ tests/
      - run: luau-analyze --mode=strict src/
      - run: lune run scripts/run-tests.luau
```

Add a deploy job (place publishing via Open Cloud) that runs only on `main` push.

## What you don't need to test

- **Roblox engine APIs themselves.** You don't need to verify that `Vector3.new(1, 2, 3)` returns a Vector3.
- **Trivial getters/setters.** If a function literally returns a field, the test reads exactly the same as the function body.
- **UI rendering pixel-perfect.** Hard to do, low payoff. Test the state behind the UI, not the visuals.

## Common gotchas

- **`task.wait` in tests** — be careful. Tests should be deterministic. Use fake timers (Jest-Lua has them) or design code to accept a clock dependency.
- **DataStores in Studio** are real (using a Studio-only mock backing store) but have quirks. Don't assert on exact internal state; use the same query API you'd use in production.
- **Playtest startup cost is high** — a few seconds per playtest. Budget your CI time accordingly. If you're running 100 tests, don't fire up a playtest for each.

## Reading list

- Jest-Lua: `https://github.com/jsdotlua/jest-lua`
- TestEZ: `https://github.com/Roblox/testez`
- luau-analyze docs: `https://luau.org/typecheck`
- Roblox Studio playtest agent announcement: `https://about.roblox.com/newsroom/2026/04/roblox-studio-going-agentic`
