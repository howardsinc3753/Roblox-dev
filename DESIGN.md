# Dragon Warz - Game Design Document

> This is the shared brain between you and Claude Code. Update this as the design evolves.
> Claude Code reads this at the start of every session to understand intent.

## Game Title
**Dragon Warz**

## Genre / Core Loop
Free-for-all aerial combat. Players pick a dragon, fly around a floating island arena, and fight each other with elemental breath attacks and abilities. Last dragon standing wins the round. Rounds are short (2-3 minutes). Between rounds, players earn coins and can upgrade or switch dragons.

**30-second loop**: Fly around → spot enemy → close distance → fire breath attack → dodge their attack → finish them or retreat to heal.

## Target Audience
Casual Roblox players ages 9-16 who enjoy PvP combat games, dragon themes, and pick-up-and-play action.

## Mechanics

### Mechanic 1: Dragon Selection
- Description: Players choose from a roster of dragons, each with unique stats and breath type
- Data: DragonId, element, health, speed, damage, special ability
- Rules: Start with 2 unlocked dragons. Earn coins to unlock more.

| Dragon | Element | HP | Speed | Damage | Special |
|--------|---------|-----|-------|--------|---------|
| Ember | Fire | 100 | 50 | 15 | Fireball burst (AoE) |
| Frost | Ice | 120 | 40 | 12 | Ice wall (shield) |
| Storm | Lightning | 80 | 60 | 18 | Chain lightning (multi-hit) |
| Terra | Earth | 150 | 35 | 10 | Rock armor (+50 HP) |
| Shadow | Dark | 90 | 55 | 14 | Invisibility (3s) |
| Prism | Light | 100 | 50 | 13 | Heal pulse (heal nearby allies) |

### Mechanic 2: Flight
- Description: All dragons fly freely in 3D space. No walking.
- Data: Position, velocity, pitch/yaw, boost meter
- Rules:
  - WASD/arrow keys for directional movement
  - Mouse to look/aim
  - Space to ascend, Shift to descend
  - Q for boost (drains boost meter, recharges over time)
  - Boost meter: 100 max, drains 25/sec while boosting, recharges 10/sec

### Mechanic 3: Combat
- Description: Breath attacks and special abilities
- Data: Cooldowns, damage, projectile speed, range
- Rules:
  - Left click: Breath attack (element-colored projectile, 1s cooldown)
  - Right click / E: Special ability (10s cooldown)
  - Damage numbers float above hit targets
  - KO = respawn after 5s at random spawn point
  - Kills award 10 coins + 1 point on scoreboard

### Mechanic 4: Rounds
- Description: Timed free-for-all rounds
- Rules:
  - Round duration: 120 seconds
  - 15-second intermission between rounds (dragon select screen)
  - Scoreboard shows kills/deaths/points
  - Round winner announced (most kills)

## Progression
- **Coins**: Earned from kills (10) and round participation (5). Persist across sessions.
- **Dragon unlocks**: Ember and Frost are free. Storm costs 100, Terra 150, Shadow 200, Prism 300.
- **Future**: Dragon skins, particle effects, emotes (stretch goals, not MVP).

## Monetization (stretch goal, not MVP)
- **Game Pass: "All Dragons"** — unlocks all dragons immediately (99 Robux)
- **Game Pass: "2x Coins"** — doubles coin earnings (49 Robux)
- **Developer Product: "50 Coins"** — buy coins directly (25 Robux)

## Data Model

```luau
type PlayerData = {
    coins: number,
    unlockedDragons: { [string]: boolean },
    selectedDragon: string,
    stats: {
        totalKills: number,
        totalDeaths: number,
        gamesPlayed: number,
    },
}

-- Default for new players
local DEFAULT_DATA: PlayerData = {
    coins = 0,
    unlockedDragons = { Ember = true, Frost = true },
    selectedDragon = "Ember",
    stats = { totalKills = 0, totalDeaths = 0, gamesPlayed = 0 },
}
```

## Network Events

| Name | Direction | Payload | Purpose |
|------|-----------|---------|---------|
| SelectDragon | Client → Server | dragonId: string | Player picks a dragon |
| UnlockDragon | Client → Server | dragonId: string | Player buys a dragon with coins |
| FireBreath | Client → Server | origin: Vector3, direction: Vector3 | Breath attack fired |
| UseSpecial | Client → Server | (none) | Special ability activated |
| DamagePlayer | Server → Client | targetId: number, damage: number | Show damage number |
| PlayerKO | Server → All | killerId: number, victimId: number | KO notification |
| RoundStart | Server → All | roundNumber: number, duration: number | Round begins |
| RoundEnd | Server → All | winnerId: number, scoreboard: {} | Round over |
| UpdateCoins | Server → Client | coins: number | Coin balance changed |
| GetPlayerData | Client → Server | (none) → PlayerData | Load player data on join |

## Map / World Layout
- **Floating islands arena**: A cluster of floating rock islands at different heights
- Sky background, clouds below and around
- 4-6 spawn points on different islands
- Central large island with a crystal (visual landmark, no gameplay function yet)
- Arena boundary: invisible walls or kill zone ~500 studs from center
- Vertical play space: ground level to ~200 studs up

## Art Direction
- Fantasy-cartoon style (not realistic). Bright, saturated colors.
- Each dragon element has a distinct color scheme:
  - Fire: red/orange, Frost: blue/white, Storm: yellow/purple
  - Terra: brown/green, Shadow: black/purple, Prism: white/rainbow
- Floating islands: mossy stone, crystal formations
- Sky: sunset gradient (orange → purple → dark blue)

## Audio
- Epic fantasy background music (looping)
- SFX: wing flaps, breath attacks (element-specific), hit sounds, KO explosion
- Round start fanfare, round end fanfare
- Dragon roar on special ability

## Milestones
- [x] Project scaffold and design doc
- [ ] Prototype: flight + breath attack in an empty arena
- [ ] Core: dragon selection, combat, KO/respawn, round system
- [ ] Data: coin economy, dragon unlocks, DataStore persistence
- [ ] Polish: UI (HUD, scoreboard, dragon select), SFX, arena decoration
- [ ] Launch: publish to Roblox
