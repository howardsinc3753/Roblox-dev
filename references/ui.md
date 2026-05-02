# UI

Roblox UI is built from `Frame`, `TextLabel`, `TextButton`, `ImageLabel`, `ScrollingFrame`, `UIGridLayout`, `UICorner`, etc. — instances parented to a `ScreenGui`. You can write code that mutates these directly, but for any non-trivial UI you'll want a framework.

## Pick one

For new projects in 2026:

| Framework | When to pick it |
|---|---|
| **React-lua** (`jsdotlua/react`) | You know React. You want hooks, functional components, the broader React mental model. Roblox-maintained internally. |
| **Fusion** (`elttob/fusion`) | You don't know React. You like state-driven, scope-based code. Roblox-native idioms. Lighter weight. |
| **Roact** | Don't pick this. **Deprecated**. You'll see it in older codebases — when you do, plan to migrate. |
| **Manual** (no framework) | One-screen UIs. Loading screens. Simple HUD elements. Adding a framework would be more code than the UI. |

Both React-lua and Fusion are fine. The React port is more familiar to web devs and has better tooling (DevTools, Storybook). Fusion is more idiomatic to Luau and has slightly less ceremony.

## React-lua (`jsdotlua/react`)

The community-maintained fork of React-lua, kept current. The original Roblox-internal version powers most Roblox-made plugins and the Roblox Universal App (the desktop console UI), so it's battle-tested.

### Install via Wally

```toml
# wally.toml
[dependencies]
React = "jsdotlua/react@17.1.0"
ReactRoblox = "jsdotlua/react-roblox@17.1.0"
```

`wally install`. The packages land in `Packages/`. Map that directory into ReplicatedStorage in your `default.project.json`.

### Minimal example

```luau
-- src/client/UI/Counter.luau
local React = require(ReplicatedStorage.Packages.React)
local e = React.createElement

local function Counter()
    local count, setCount = React.useState(0)
    return e("Frame", {
        Size = UDim2.fromScale(0.3, 0.2),
        Position = UDim2.fromScale(0.35, 0.4),
        BackgroundColor3 = Color3.fromRGB(40, 40, 40),
    }, {
        Label = e("TextLabel", {
            Size = UDim2.fromScale(1, 0.5),
            Text = `Count: {count}`,
            TextColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 1,
        }),
        Button = e("TextButton", {
            Size = UDim2.fromScale(1, 0.5),
            Position = UDim2.fromScale(0, 0.5),
            Text = "Click me",
            [React.Event.Activated] = function() setCount(count + 1) end,
        }),
    })
end

return Counter
```

Mount it:

```luau
-- src/client/init.client.luau
local Players = game:GetService("Players")
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local React = require(ReplicatedStorage.Packages.React)
local Counter = require(script.UI.Counter)

local container = Instance.new("ScreenGui")
container.Parent = Players.LocalPlayer.PlayerGui

local root = ReactRoblox.createRoot(container)
root:render(React.createElement(Counter))
```

### What carries over from React (web)

- `useState`, `useEffect`, `useMemo`, `useCallback`, `useRef`, `useContext` — all work the same.
- `React.createElement` (no JSX, but `e = React.createElement` is the convention).
- Functional components first, class components possible but rare.
- Refs target Roblox Instances instead of DOM nodes.
- Event handlers use `[React.Event.Activated]` (button click), `[React.Event.MouseEnter]`, etc. — bracketed because they're indexed by `RBXScriptSignal` symbols.
- Property changed events use `[React.Change.Text]`, etc.

### Important Roblox-specific bits

- **Use `React.createElement`-as-`e` consistently.** Don't fight it.
- **Children are passed as a table** keyed by name. The keys become the Instance names (handy for Studio inspection).
- **State updates are batched.** `useEffect` with cleanup works the same as web.
- **No JSX.** Some teams use roblox-ts to get JSX (compiles to `React.createElement` calls). If JSX matters to you, that's a strong reason to use roblox-ts.

### roblox-ts + React

If you're on roblox-ts: `npm i @rbxts/react @rbxts/react-roblox`. JSX works. Type definitions are excellent. This is the closest you can get to "writing modern React for Roblox".

## Fusion (`elttob/fusion`)

Fusion is a state graph framework: you create reactive `Value` objects, derive `Computed` values from them, and bind UI properties to those values. When a `Value` changes, every dependent `Computed` and bound property updates automatically. No virtual DOM, no reconciliation — direct updates.

### Install via Wally

```toml
[dependencies]
Fusion = "elttob/fusion@0.3.0"
```

### Minimal example

```luau
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local scoped, peek = Fusion.scoped, Fusion.peek
local New, Children, OnEvent = Fusion.New, Fusion.Children, Fusion.OnEvent

local scope = scoped(Fusion)
local count = scope:Value(0)

local ui = scope:New "ScreenGui" {
    Parent = Players.LocalPlayer.PlayerGui,
    [Children] = {
        scope:New "Frame" {
            Size = UDim2.fromScale(0.3, 0.2),
            Position = UDim2.fromScale(0.35, 0.4),
            BackgroundColor3 = Color3.fromRGB(40, 40, 40),
            [Children] = {
                scope:New "TextLabel" {
                    Size = UDim2.fromScale(1, 0.5),
                    Text = scope:Computed(function(use)
                        return `Count: {use(count)}`
                    end),
                    BackgroundTransparency = 1,
                    TextColor3 = Color3.new(1, 1, 1),
                },
                scope:New "TextButton" {
                    Size = UDim2.fromScale(1, 0.5),
                    Position = UDim2.fromScale(0, 0.5),
                    Text = "Click me",
                    [OnEvent "Activated"] = function()
                        count:set(peek(count) + 1)
                    end,
                },
            },
        },
    },
}

-- Cleanup later:
-- scope:doCleanup()
```

### When Fusion shines

- State that's a graph of derivations (HP → HP percentage → color → bar fill) — Fusion's reactive model is perfect.
- Animations and tweens — Fusion has `Tween` and `Spring` first-class.
- You want to reason about cleanup explicitly via scopes (no surprise leaks).

### When Fusion struggles

- Component reuse patterns (Fusion has them, but they're more verbose than React's component composition).
- Conditional rendering — Fusion has `Hydrate` and patterns for it, but it's less ergonomic than React's `{cond && <Thing />}`.

## Storybook for Roblox: UI Labs

`http://ui-labs.luau.page/`. Storybook-style plugin for Roblox. Lets you develop UI components in isolation without launching the full game. Supports both React-lua and Fusion. Highly recommended for any project with > 5 components.

```toml
[dev-dependencies]
UILabs = "pepeeltoro41/ui-labs@2.0.0"
```

Each component gets a `*.story.luau` file. The plugin scans for stories and renders them in a Studio panel.

## Layout primitives to know

These show up in nearly every Roblox UI:

- `UIListLayout` — flex-style row/column with auto-sort, padding, alignment
- `UIGridLayout` — equal-cell grid
- `UIPadding` — internal padding for any GuiObject
- `UICorner` — rounded corners
- `UIStroke` — outlined borders, with `ApplyStrokeMode` for either contained or bordered
- `UIScale`, `UISizeConstraint`, `UIAspectRatioConstraint` — responsive sizing
- `UIGradient` — gradient fills, animatable

`AutomaticSize = Enum.AutomaticSize.XY` on a frame with a `UIListLayout` child gives you content-sized panels. Combine with `UIPadding` for the equivalent of CSS box-sizing with padding.

## Sizing: UDim2

Every position and size is a `UDim2`: `UDim2.new(scaleX, offsetX, scaleY, offsetY)`.

- `UDim2.fromScale(0.5, 0.5)` — 50% of parent. Use for responsive layouts.
- `UDim2.fromOffset(100, 50)` — 100×50 pixels. Use for text fields, buttons.
- Mix: `UDim2.new(1, -20, 0, 50)` — full width minus 20px, 50px tall. Common for padded full-width rows.

## Common gotchas

- **`AnchorPoint`** controls what point on the GuiObject `Position` refers to. `AnchorPoint = Vector2.new(0.5, 0.5)` means the GuiObject's center sits at its `Position`. Default `(0, 0)` (top-left) frequently surprises React devs used to CSS `transform: translate(-50%, -50%)`.
- **`ZIndex`** on GuiObjects controls overlap order. `ZIndexBehavior` on the parent ScreenGui can be `Sibling` (default — only siblings compare) or `Global` (entire ScreenGui compared). For complex z-stacks, set Global.
- **Text scaling**: `TextScaled = true` makes text fill the GuiObject. With multi-line, use `TextWrapped`. Combine with `UITextSizeConstraint` to clamp.
- **Performance**: render lots of items with `ScrollingFrame` + `UIListLayout` and only render visible ones (virtualized lists). Native virtualization isn't built in; libraries like `RactReact` or hand-rolled virtual scroll exist.

## Reading list

- React-lua how-to (official Roblox staff guide): search DevForum "How To: React + Roblox"
- React-lua repo: `https://github.com/jsdotlua/react-lua`
- Fusion docs: `https://elttob.uk/Fusion/`
- UI Labs: `http://ui-labs.luau.page/`
- Roblox Creator Docs UI section: `https://create.roblox.com/docs/ui`
