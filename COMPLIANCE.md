# Dragon Warz — Compliance & Age Rating Checklist

Things to set in Creator Hub before publishing for under-13 audiences.
Roblox auto-pulls non-compliant places, so these aren't optional.

## Required: Experience Age Rating

In Creator Hub → your experience → **Configure → Experience Maturity**:

Pick the lowest tier the content qualifies for. For Dragon Warz (cartoon
dragon combat, no realistic violence/blood, no chat-driven content):

| Setting | Value | Why |
|---------|-------|-----|
| **Age Rating** | `Mild (9+)` | Cartoon fantasy combat is in the "Mild" tier, not "Minimal" — Minimal is for sandbox/puzzle/builder games with zero combat |
| **Realistic Violence** | `None` | Stylized dragons hitting each other isn't realistic violence. Don't claim this even if you think the breath effects look intense |
| **Sound-based Violence** | `None` | KO sound is a soft thump, not gore |
| **Crude Humor** | `None` | We have no chat or text content |
| **Romance** | `None` | N/A |
| **Free-form Communication** | `None` | We have no in-game chat |
| **Player Communication** | `None unless you enable Roblox chat in your Place Settings` |
| **Social Hangout** | `None` | This is a combat game, not hangout |
| **Gambling** | `None` | No coin-flip mechanics; coins are skill-earned, no random rolls |
| **Blood and Gore** | `None` | Dragons don't bleed |
| **Drugs and Alcohol** | `None` | N/A |

After publishing the maturity questionnaire, Roblox displays "9+" on
your experience tile. Players under 9 can still play if their parent
account allows it.

## Required: Disable Free-Form Text Input

By default, Roblox includes a chat window. For under-13 audiences, ALL
text passes through Roblox's TextChatService which filters via TextService.
We don't add any custom chat — the default Roblox filter is sufficient.

In Creator Hub → **Game Settings → Permissions**:
- [ ] **Bubble Chat**: ON (Roblox-filtered, kid-safe)
- [ ] **Chat Window**: ON (Roblox-filtered, kid-safe)
- [ ] **Custom chat with player input**: OFF (we don't have any)

Anything in our code that displays a player's name (kill feed, leaderboard,
welcome banner) uses `Player.Name` directly — Roblox names are pre-screened
when accounts are created, no further filtering needed.

## Required: HTTP Requests Setting

In Creator Hub → **Game Settings → Security**:
- [ ] **Allow HTTP Requests**: ON

This is needed because:
- The game makes no outbound HTTP calls today (everything routes through
  Open Cloud at deploy time, not runtime)
- BUT having it on lets us add features later (Open Cloud calls from
  inside the game) without needing to ship a settings change

## Required: Studio Access to API Services

In Creator Hub → **Game Settings → Security**:
- [ ] **Enable Studio Access to API Services**: ON (you already did this)

## Recommended: Permission Settings

In Creator Hub → **Game Settings → Permissions**:

| Setting | Value | Notes |
|---------|-------|-------|
| **Public** | ON for launch | Required for kids' friends to find via search |
| **Private Servers (Game Passes)** | OFF (for now) | Future monetization, not needed for MVP |
| **Copying** | OFF | Prevents people stealing the place + republishing |
| **Comments** | OFF (for now) | Comments require moderation; revisit when you have time |

## Recommended: Monetization Settings

In Creator Hub → **Monetization**:

For launch, leave all monetization OFF. Game Passes and Developer Products
require manual review by Roblox before they can be sold; setting up the
infrastructure now without anything for sale is fine.

When you add the "All Dragons" Game Pass later (~99 R$):
1. Create the Game Pass via Creator Hub
2. Note the GamePassID it gives you
3. Wire it into `DataManager` — on join, check
   `MarketplaceService:UserOwnsGamePassAsync(player.UserId, GAMEPASS_ID)`
   and if true, unlock all dragons

## Required: Place Description

Plain language, no marketing fluff. Roblox's moderation prefers clear
descriptions of what the experience contains.

Suggested copy for Dragon Warz:

> Dragon Warz is a free-for-all aerial combat game where you pick from 6
> elemental dragons (Fire, Ice, Lightning, Earth, Shadow, Light) and battle
> other players + AI enemies in a floating-island arena. Survive waves of
> enemy dragons and outscore other players to win 2-minute rounds. Earn
> coins to unlock new dragons. Cartoon fantasy combat — no blood, no
> realistic violence. Best with PS5/Xbox controller or keyboard+mouse.

## Required: Thumbnail / Icon

In Creator Hub → **Configure → Basic Info**:

- **Icon**: 512×512 PNG. Use the Ember dragon preview render or a stylized
  dragon-fight scene. AVOID screenshots that look "too realistic" — Roblox
  rates by both code-declared maturity AND image content.
- **Thumbnails**: 5-10 screenshots showing combat action, the dragon select
  UI, the arena. Helps with discovery.

## Recommended: Region Restrictions

In Creator Hub → **Game Settings → Localization**:

For initial launch, leave region restrictions OFF (worldwide). If you see
moderation issues from a specific region, you can restrict later.

Note for Mainland China: Roblox runs `roblox.qq.com` separately. Open Cloud
features (our deploy pipeline) don't work for that platform. If your kids'
friends are in mainland China, they'll need a separate publishing flow.

## Pre-Launch Final Check

Before clicking "Publish" the first time:

- [ ] All settings above configured
- [ ] Tested in Studio with `STUDIO_FRESH_PLAYER` workspace attribute toggled ON
      to confirm new-player experience works (no debug coins/dragons)
- [ ] Ran `lune run scripts/deploy.luau --saved` successfully
- [ ] Loaded the saved version in Creator Hub, played a full round, no errors
- [ ] Mesh validation script ran clean for all 6 dragons
- [ ] Reviewed your kids' Roblox accounts — they can be added as Friends
      so the place shows up in their feed

When all green, run:
```
lune run scripts/deploy.luau --published
```

Then share the URL: `https://www.roblox.com/games/<PLACE_ID>/Dragon-Warz`
