# Roblox Game Dev

Roblox game project built with Luau + Rojo + Claude Code AI workflow.

## Setup

1. Install [Roblox Studio](https://create.roblox.com/)
2. Install [Rokit](https://github.com/rojo-rbx/rokit) (toolchain manager)
3. Run `rokit install` to get Rojo, Wally, Lune, StyLua, Selene
4. Run `wally install` to install packages
5. Run `rojo serve` to start live-sync to Studio
6. In Studio: connect to the Rojo plugin

## Project Structure

- `src/` — Game source code (server, client, shared modules)
- `references/` — AI corpus docs for Claude Code
- `scripts/` — Build, deploy, and automation scripts (Lune)
- `tests/` — Jest-Lua test specs
- `assets/` — Audio, models, textures
- `DESIGN.md` — Game design document
- `CLAUDE.md` — Claude Code AI workflow configuration
