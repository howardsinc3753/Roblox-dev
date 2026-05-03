# Dragon Warz — Publishing Guide

The complete checklist for getting Dragon Warz from Studio to live on Roblox.com,
plus what to set in Creator Hub before you tell the kids it's playable.

## One-time setup (do once, then forget)

### 1. Publish the place to Roblox (creates the IDs we need)

In Studio:

1. **File → Publish to Roblox** (NOT "Save to Roblox" — Publish creates a new
   experience; Save just saves to an existing one)
2. **Create a new experience** → name it `Dragon Warz`
3. **Description**: pick anything for now; you can refine later in Creator Hub
4. **Genre**: Action
5. **Maximum Players**: 12 (matches our NPC cap; bigger lobbies will lag)
6. Click **Create** — it will publish and give the place a Place ID

### 2. Get your Place ID + Universe ID

1. Go to <https://create.roblox.com/dashboard/creations>
2. Click your `Dragon Warz` experience tile
3. The URL now looks like: `create.roblox.com/dashboard/creations/experience/<UNIVERSE_ID>/places/<PLACE_ID>`
4. Copy both numeric IDs

### 3. Wire them into the deploy script

Two ways. Pick one:

**Option A — Local config file (quick start)**
```bash
cp deploy.config.example.json deploy.config.json
# Edit deploy.config.json, paste in your real IDs
```
The file is gitignored so it stays on your machine.

**Option B — Environment variables (better for CI)**
Add to your `.env`:
```
PLACE_ID=123456789
UNIVERSE_ID=987654321
```

### 4. Verify the API key has the right scope

The Open Cloud API key in `.env` (`ROBLOX_API_KEY`) needs the
**`universe-places:write`** scope to publish places. To check / fix:

1. <https://create.roblox.com/dashboard/credentials>
2. Click your existing API key
3. **API System Access** section → make sure **Place Publishing** is allowed for your universe
4. If not, edit, add the universe + permission, save

## Deploy commands

After the one-time setup:

```bash
# Saved (visible to you only — for testing the deployed build before going live)
lune run scripts/deploy.luau

# Or explicitly:
lune run scripts/deploy.luau --saved

# Live to all players:
lune run scripts/deploy.luau --published
```

The script:
1. Runs `rojo build` to produce `build/dragon-warz.rbxlx`
2. Sanity-checks the file exists and isn't suspiciously empty
3. PATCHes it to the Open Cloud Place Publishing endpoint
4. Prints the result

A typical successful run takes 5-15 seconds.

## CI/CD via GitHub Actions

The workflow at `.github/workflows/deploy.yml` runs the same script in CI:

- **On push to main**: deploys as `Saved` (won't auto-ship to players)
- **Manually via workflow_dispatch**: deploys as `Published` (live)

To enable, set these in your GitHub repo:

1. **Repo Settings → Secrets and variables → Actions**
2. **Secrets** tab → New secret: `ROBLOX_API_KEY` → paste the same key from `.env`
3. **Variables** tab → New variable: `PLACE_ID` → paste your place ID
4. **Variables** tab → New variable: `UNIVERSE_ID` → paste your universe ID

After this, every push to `main` builds and saves a new version to your test
slot. To go live, click **Actions → Deploy to Roblox → Run workflow → check the
"Publish live" box → Run**.

## Pre-launch Creator Hub checklist

Before the kids play, configure these in
<https://create.roblox.com/dashboard/creations> → your experience:

### Required
- [ ] **Game Settings → Basic Info**
  - [ ] Name: `Dragon Warz`
  - [ ] Description: 2-3 sentence pitch
  - [ ] Thumbnail/icon: 512×512 PNG (use one of the Meshy dragon previews?)
  - [ ] Genre: Action
- [ ] **Game Settings → Permissions**
  - [ ] Public (anyone can play) — or Friends only if you want a soft launch
- [ ] **Game Settings → Security**
  - [ ] **Allow HTTP Requests**: ON (needed for Open Cloud calls from inside the game, future-proofing)
  - [ ] **Enable Studio Access to API Services**: ON (you already did this)
- [ ] **Game Settings → Maturity**
  - [ ] Age rating: pick the right tier (probably "Mild" for cartoon combat)

### Recommended
- [ ] **Game Settings → Avatar**
  - [ ] Player Choice (R6/R15) — doesn't matter much because we replace the
    character with a dragon model on spawn, but Roblox needs a default
- [ ] **Game Settings → World**
  - [ ] WorldType: FlatTerrain (we don't use Roblox terrain)
  - [ ] Gravity: 196.2 (default — our flight overrides this anyway)
- [ ] **Monetization → Game Passes / Developer Products**
  - [ ] (Future) "All Dragons" gamepass — instant unlock all 6
  - [ ] (Future) "2x Coins" gamepass
  - [ ] (Future) Coin packs as Developer Products

### Polish (not required to launch)
- [ ] Upload 5-10 thumbnails showing combat, dragons, arena
- [ ] Upload a 30-second trailer video
- [ ] Add tags: `dragon`, `pvp`, `combat`, `flight`, `survival`
- [ ] Pick a primary genre + secondary genres for discovery

## Sharing the game with the kids

Once published:

1. Go to your experience in Creator Hub
2. Top-right: **Configure → Share** OR copy the URL of the place page
3. The URL pattern is `https://www.roblox.com/games/<PLACE_ID>/Dragon-Warz`
4. The kids can:
   - Open Roblox on PS5/Xbox/PC/mobile
   - Search "Dragon Warz" (works once the experience is public + indexed, ~24h)
   - OR paste the URL directly
   - Click Play → in 30 seconds they're flying

## Common deploy errors

| Error | Cause | Fix |
|-------|-------|-----|
| `401 Unauthorized` | API key missing or wrong scope | Re-check key + add `universe-places:write` scope to your universe |
| `403 Forbidden` | API key has wrong universe in its allowlist | Edit key, add the universe ID under "API System Access → Place Publishing" |
| `404 Not Found` | PLACE_ID or UNIVERSE_ID typo | Verify both in the Creator Hub URL |
| `429 Rate Limited` | Too many publish requests | Wait a minute, retry. Open Cloud is generous on Place Publishing but not infinite |
| `Build output suspiciously small` | Rojo build produced an empty file | Check `default.project.json` for syntax errors; run `rojo build` manually to see errors |

## Rolling back a bad deploy

The Open Cloud API publishes a new version each call. To roll back:

1. Creator Hub → experience → **Versions** tab
2. Pick the previous good version
3. Click **Revert**

Reversions are instant; players get the old version on next join.
