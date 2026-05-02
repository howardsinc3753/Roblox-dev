# Game Design Document

> This is the shared brain between you and Claude Code. Update this as the design evolves.
> Claude Code reads this at the start of every session to understand intent.

## Game Title
[Working title here]

## Genre / Core Loop
[What is the game? What does the player do every 30 seconds?]

## Target Audience
[Who is this for? Age range, Roblox player profile]

## Mechanics
[List the core mechanics. Be specific about data structures and rules.]

### Mechanic 1: [Name]
- Description:
- Data: 
- Rules:

### Mechanic 2: [Name]
- Description:
- Data:
- Rules:

## Progression
[How does the player grow? Levels, unlocks, prestige/rebirth?]

## Monetization
[Game Passes, Developer Products, cosmetics, etc.]

## Data Model
[What gets saved per player? DataStore schema.]

```luau
-- Example player data shape
type PlayerData = {
    coins: number,
    level: number,
    inventory: { [string]: number },
    -- add fields as design evolves
}
```

## Network Events
[RemoteEvents and RemoteFunctions the game needs]

| Name | Direction | Payload | Purpose |
|------|-----------|---------|---------|
| | | | |

## Map / World Layout
[Describe zones, areas, spawn points. Visual layout is done in Studio.]

## Art Direction
[Style notes: realistic, low-poly, cartoony? Color palette?]

## Audio
[Music vibe, SFX needs, NPC voiceover characters]

## Milestones
- [ ] Prototype: core loop playable
- [ ] Alpha: progression + monetization wired
- [ ] Beta: polish, testing, friends playtest
- [ ] Launch: publish to Roblox
