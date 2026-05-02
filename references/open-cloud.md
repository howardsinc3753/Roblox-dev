# Open Cloud — Roblox's REST API surface

Open Cloud is Roblox's official HTTP API for everything that happens *outside* the running game engine: deploying place files, uploading assets, reading and writing datastores, sending messages to live servers, managing universes and developer products. If you want to automate Roblox from a CI pipeline, a Discord bot, a web dashboard, or a Lune script, this is the surface.

As of March 2026, Roblox unified the documentation: `https://create.roblox.com/docs/cloud`. All previously-fragmented "Cloud V1", "Cloud V2", and "Legacy" endpoints now live under a single reference, indexed both by domain (`groups.roblox.com`, `apis.roblox.com`) and by use-case (Users, Groups, Datastores, etc.).

## Authentication

Two methods. Pick based on the use case:

### API Keys (recommended for most automation)

Created at `https://create.roblox.com/dashboard/credentials`. Scoped to specific universes and specific permissions (read/write datastores, publish places, upload assets, etc.). Header:

```
x-api-key: YOUR_API_KEY_HERE
```

Important: as of late 2025, API keys can optionally be granted access to *all* your experiences (saves the friction of re-scoping every time you make a new game). Set this in the key creation flow.

API keys for groups: a key created on a group's developer dashboard inherits group-level permissions.

### OAuth 2.0 (for apps that act on behalf of users)

Standard OAuth flow with `https://apis.roblox.com/oauth/v1/authorize` and `https://apis.roblox.com/oauth/v1/token`. Needed when your tool acts on behalf of *other* Roblox users, not yourself — third-party dashboards, group management tools, etc.

Use API keys unless you specifically need OAuth.

## The high-leverage endpoints

These are the ones to know cold:

### Datastores — store/retrieve game data from outside

`apis.roblox.com/datastores/v1/universes/{universeId}/standard-datastores/datastore/entries`

- `GET .../entry` — read a key
- `POST .../entry` — write a key
- `DELETE .../entry` — delete
- `GET .../entries` — list keys (paginated)
- `GET .../versions` — list historical versions
- Ordered datastores live at a separate endpoint, useful for leaderboards

Use cases: scheduled migrations, off-platform admin tools, automated backups, importing player data from another platform.

```bash
curl -X GET "https://apis.roblox.com/datastores/v1/universes/${UNIVERSE_ID}/standard-datastores/datastore/entries/entry?datastoreName=PlayerData&entryKey=player_123" \
  -H "x-api-key: ${ROBLOX_API_KEY}"
```

### Messaging — push to live servers

`apis.roblox.com/messaging-service/v1/universes/{universeId}/topics/{topic}`

POST a payload, every running server in the universe gets it via `MessagingService:SubscribeAsync(topic)`. Use cases: global announcements, hot-reload signals, cross-server events. **Note: messages from Open Cloud only arrive in live game servers, not Studio playtests.**

```bash
curl -X POST "https://apis.roblox.com/messaging-service/v1/universes/${UNIVERSE_ID}/topics/global-announce" \
  -H "x-api-key: ${ROBLOX_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"message": "Server restart in 5 minutes"}'
```

### Assets — upload and update assets programmatically

`apis.roblox.com/assets/v1/assets`

Currently supports: **Decals** (images for UI/textures), **Audio** (MP3/OGG sound effects, music, voiceover), **Models** (FBX). 

This is the endpoint that makes the ElevenLabs → Roblox audio pipeline work (see `assets-audio.md`). Also lets you batch-upload textures or models from a Blender export script.

```bash
# Upload a decal
curl -X POST "https://apis.roblox.com/assets/v1/assets" \
  -H "x-api-key: ${ROBLOX_API_KEY}" \
  -F 'request={"assetType":"Decal","displayName":"My Texture","description":"...","creationContext":{"creator":{"userId":"123456"}}}' \
  -F "fileContent=@my-texture.png"
```

The response contains an operation ID. Poll the operation endpoint until status is `Done` to get the final asset ID. Use that ID as `rbxassetid://...` in-game.

### Place publishing — deploy from CI

`apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType={Saved|Published}`

PATCH a place file (.rbxl or .rbxlx). `Saved` = Studio "Save" equivalent. `Published` = visible to players.

This pairs perfectly with `rojo build`:

```bash
rojo build default.project.json -o build/game.rbxlx
curl -X POST "https://apis.roblox.com/universes/v1/${UNIVERSE_ID}/places/${PLACE_ID}/versions?versionType=Published" \
  -H "x-api-key: ${ROBLOX_API_KEY}" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@build/game.rbxlx"
```

Drop that into a GitHub Actions workflow on push-to-main and you have CD.

### Developer Products and Game Passes (Dec 2025)

`apis.roblox.com/cloud/v2/universes/{universeId}/developer-products` and `.../game-passes`. Create, fetch, update, list. Useful for programmatic monetization workflows (creating products via a CI step rather than clicking through the dashboard).

### Engine API for scripts (beta, since 2024)

Lets you read/edit scripts in a published place from outside Studio. Use case: bulk script edits, automated migrations, AI-driven refactors that don't require a live Studio session.

## Calling Open Cloud from inside the game

As of May 2025, `HttpService` in Roblox can directly call Open Cloud endpoints (apis.roblox.com, www.roblox.com) without needing a proxy server. Big deal — previously you had to host your own proxy because Roblox blocked direct access to its own domains, which was annoying and a security smell.

This unlocks: changing a group member's rank from in-game, writing to a datastore of *another* experience you own, programmatic universe management triggered by gameplay events.

```luau
local HttpService = game:GetService("HttpService")
local response = HttpService:RequestAsync({
    Url = "https://apis.roblox.com/messaging-service/v1/universes/123/topics/test",
    Method = "POST",
    Headers = {
        ["x-api-key"] = "YOUR_KEY",
        ["Content-Type"] = "application/json",
    },
    Body = HttpService:JSONEncode({ message = "from in-game!" })
})
```

Don't hardcode keys in the source — keep them in a server-only ModuleScript that's not in the Rojo project, or fetch from your own auth backend.

## Patterns for Claude Code automation

### Pattern 1: Lune scripts in `scripts/`

Drop Open Cloud calls into `scripts/*.luau`, run with Lune. Examples:

```luau
-- scripts/upload-audio.luau
local net = require("@lune/net")
local fs = require("@lune/fs")
local process = require("@lune/process")

local apiKey = process.env.ROBLOX_API_KEY
local userId = process.env.ROBLOX_USER_ID
local audioPath = process.args[1]

-- multipart/form-data upload omitted for brevity
-- (use net.request with body = serialized multipart)
```

This is the cleanest place to put one-off ops. Commit them to the repo so the team has a record.

### Pattern 2: GitHub Actions for deploy

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ok-nick/setup-aftman@v0  # or rokit
      - run: aftman install
      - run: rojo build default.project.json -o build/game.rbxlx
      - name: Publish to Roblox
        env:
          ROBLOX_API_KEY: ${{ secrets.ROBLOX_API_KEY }}
        run: |
          curl -X POST "https://apis.roblox.com/universes/v1/${{ vars.UNIVERSE_ID }}/places/${{ vars.PLACE_ID }}/versions?versionType=Published" \
            -H "x-api-key: ${ROBLOX_API_KEY}" \
            -H "Content-Type: application/octet-stream" \
            --data-binary "@build/game.rbxlx"
```

### Pattern 3: SDK wrappers

If you're doing more than a couple of calls, use a wrapper:

- **Python**: `rblx-open-cloud` (`pip install rblx-open-cloud~=2.0`). Sync and async, OAuth flow built-in, operation polling and retries.
- **Node.js**: search npm for `roblox-open-cloud` or `noblox.js` (broader Roblox API coverage including legacy).
- **Lune**: `net.request` directly — there's no Roblox-specific Lune wrapper but the API is close enough to raw HTTP that you don't need one.

## Rate limits and quotas

Every endpoint has limits. Notable ones:

- Datastore writes: 60/minute per user per datastore (default). Burst higher allowed.
- Messaging: 100 messages/minute per universe, 1KB max payload.
- Asset uploads: depends on type and your account history. Rate-limited; check response 429s.
- Place publishing: very generous, can publish many times per hour.

Plan bulk operations around these. For mass datastore migrations, throttle at ~30 writes/sec across keys to stay safely under the cap.

## Common gotchas

- **Universe ID ≠ Place ID.** A universe contains one or more places. The "start place" of a universe is what most game dev pages refer to. API endpoints sometimes want one, sometimes the other — read the docs carefully.
- **Operation polling.** Many write endpoints return an operation ID rather than completing synchronously. Poll the operation endpoint until `done: true`. Asset uploads in particular do this.
- **API keys leak in logs.** Treat them as secrets. Rotate after CI logs are public. Set IP allowlists in the key config when possible.
- **Game settings need to allow HTTP.** For in-game `HttpService` calls, even to Open Cloud, the universe must have "Allow HTTP Requests" enabled in Game Settings.
- **`HttpService:JSONEncode`** vs Open Cloud's expected JSON. Roblox's encoder produces slightly different output for empty arrays (`{}` vs `[]`). For Open Cloud, this usually doesn't matter, but it has bitten people on group rank endpoints. When in doubt, manually format the body.

## Reading list

- Open Cloud docs (canonical): `https://create.roblox.com/docs/cloud`
- API reference (everything in one place since March 2026): `https://create.roblox.com/docs/cloud-reference`
- Python SDK: `https://github.com/treeben77/rblx-open-cloud`
- HttpService → Open Cloud (no proxies) announcement: search DevForum "Use Open Cloud via HttpService Without Proxies"
