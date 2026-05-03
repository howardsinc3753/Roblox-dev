# 3D Assets

Three sources of 3D content for a Roblox game, in increasing order of effort and quality control:

1. **Roblox Creator Store** — built-in marketplace, free and paid models. `MarketplaceService:LoadAsset()` or Studio's Toolbox.
2. **AI generators** — Cube/Mesh Generation in Studio, Tripo3D / Meshy / Luma externally. Fast, decent quality, needs cleanup.
3. **Hand-modeled in Blender (or Maya, etc.)** → exported as FBX/OBJ → imported into Roblox. Most effort, most control.

For a Claude-Code-driven workflow, you'll often mix all three. Use Cube for placeholder props, Blender for hero assets, the Creator Store for things that already exist (vehicles, common architecture).

## Roblox unit conventions

- **Studs** are Roblox's distance unit. **One stud ≈ 0.28 meters** (from Roblox's avatar height calibration). A Roblox character is ~5 studs tall.
- **Y is up**. Z is forward (negative Z, more accurately — same as most engines).
- **Mesh poly budget**: 10,000 triangles is the practical limit per mesh part. Roblox accepts higher but performance suffers, especially on mobile.
- **Texture budget**: 1024×1024 is the recommended ceiling for most assets. 2048 is allowed for hero meshes. Use PBR (Albedo, Normal, Metalness, Roughness) via `SurfaceAppearance`.

Get these wrong and your imported model arrives as a 100-stud colossus or an invisible dot.

## Blender → Roblox pipeline

This is the canonical path for hand-modeled assets.

### Step 1: Install Blender + the Roblox Blender Plugin

- Blender (free): `https://www.blender.org/`
- Official Roblox Blender Plugin: links your Roblox account, lets you transfer 3D objects from Blender directly into an open Studio session. **This is the path of least pain.** Without the plugin you're doing manual FBX export/import every iteration.

### Step 2: Modeling for Roblox

- **Apply all transforms** before export. In Blender: select object → Object → Apply → All Transforms. Forgetting this is the #1 cause of "model arrives at wrong size or rotation" issues.
- **Clean topology**. Quads where possible, no n-gons, no overlapping faces.
- **Single-mesh per logical asset**. A chair = one mesh. Don't ship five separate parts to assemble in Studio when one merged mesh will do.
- **UV-unwrap** every mesh that needs textures. Mark seams (Ctrl+E → Mark Seam), then U → Unwrap. Pack islands tightly to maximize texel density.
- **Stay under 10K triangles** per mesh part.

### Step 3: Export as FBX with Roblox-correct settings

Roblox accepts FBX, OBJ, and glTF (`.glb`/`.gltf`). FBX is the standard choice — it carries animation data, OBJ doesn't. Export settings that work:

```
Transform:
  Apply Scaling: FBX Unit Scale
  Forward: -Z Forward
  Up: Y Up
  Apply Transform: ✓

Geometry:
  Smoothing: Face
  Export Subdivision Surface: ✗
  Apply Modifiers: ✓
  Triangulate Faces: ✓ (do this in Blender, don't trust import-time triangulation)

Armature (rigged meshes only):
  Only Deform Bones: ✓
  Add Leaf Bones: ✗
  
Animation (animated meshes):
  Bake Animation: ✓
  Sampling Rate: 1
  Simplify: 0.0
  NLA Strips / All Actions / Force Start/End Keyframes: ✗
```

### Step 4: Import into Studio

- Open the place in Studio.
- View → Asset Manager.
- Double-click "Meshes" → click the Upload icon → select your FBX.
- For rigged characters: Avatar tab → Import 3D → select FBX. Studio runs validation (joint limits, polycount, etc.) and inserts the rig.
- Apply textures: in the Properties panel of the MeshPart, set `TextureID` (basic) or add a `SurfaceAppearance` child for PBR (`ColorMap`, `NormalMap`, `MetalnessMap`, `RoughnessMap`).

For uploading textures: `Roblox.com/dashboard → Creations → Development Items → Decals → Upload`. Copy the asset ID from the URL, paste it as `rbxassetid://12345678`.

### Step 5: Test scale immediately

Drop a default `R15` character next to your imported mesh. If they're not in roughly correct proportion, **don't keep working** — go back and fix the export. Catching this early saves hours.

## AI generators in 2026

### Cube 3D / Mesh Generation (Roblox-native)

In Studio, open Assistant: `/generate a wooden treasure chest`. ~10 seconds later, a textured MeshPart drops into the workspace. Powered by Roblox's Cube foundation model (1.8B params, open-sourced March 2025).

Strengths:
- Fast iteration on placeholder/background assets
- Output is already correctly scaled to studs
- Already textured (no separate texture upload step)
- Free (no per-call cost)

Weaknesses:
- Distinct "Cube look" — fine for prototypes, may not match a stylized art direction
- No fine control over geometry (can't say "exactly 4 legs, 6 drawers")
- Can produce broken geometry on complex prompts
- One-shot — no easy way to iterate on the same mesh

### Procedural Models (Roblox-native, 2026 beta)

`Edit-Time Procedural Models` Studio beta. Generates parametric 3D models — number of staircase steps, height of bookshelf, count of building floors — that regenerate when attributes change. Built on a new `ProceduralModel` Instance type. Combine with Cube: AI builds a base model, parametrize it for variants.

### Meshy AI (recommended external generator — has MCP + Roblox Bridge)

`https://www.meshy.ai/`. Best external 3D generator for the Claude Code workflow because it has both an **MCP server** (Claude Code can drive it directly) and a **Roblox DCC Bridge** (uploads models straight to your Roblox Creator Hub).

**MCP Server install** (already configured in this project's `.mcp.json`):
```bash
npx -y @meshy-ai/meshy-mcp-server@latest
# Set MESHY_API_KEY env var
```

MCP tools available: `meshy_text_to_3d`, `meshy_image_to_3d`, `meshy_multi_image_to_3d`, `meshy_text_to_3d_refine` (add textures), `meshy_remesh` (reduce polycount).

**The correct order for Roblox-bound assets**: Generate → Remesh → Texture. Remeshing first keeps the file under Roblox's 20MB upload limit.

**Roblox Bridge**: In the Meshy web app, click DCC Bridge → Send to Roblox. OAuth authenticates against your Roblox account, uploads the GLB, and drops it in Creator Hub. From there: "Open in Studio" or "Copy Asset ID". Requires Pro tier.

**API workflow** (what Claude Code does via MCP):
1. `meshy_text_to_3d` with `mode: "preview"` → generates untextured preview mesh (~30s)
2. `meshy_text_to_3d_refine` → adds PBR textures to the preview
3. `meshy_remesh` with `target_polycount: 5000` → reduces to Roblox-safe polycount
4. Download FBX → import into Studio via Asset Manager

**Pricing**: Pro plan required. Text-to-3D preview = 20 credits, refine = varies. Check `https://docs.meshy.ai/en/api/quick-start`.

### Tripo3D / Luma (other external generators)

`https://www.tripo3d.ai/`, `https://lumalabs.ai/`. Similar text/image-to-3D services. No MCP integration — manual export workflow only.

Workflow:
1. Generate on the service's site. Pay attention to the topology mode (organic vs. hard surface).
2. Download FBX or GLB.
3. Open in Blender, apply transforms, check scale (these tools often output meshes that need 100x scale-down or scale-up to match Roblox studs).
4. Export with the Roblox FBX settings above.
5. Import into Studio.

### Material Generator and Texture Generator (Roblox-native)

Inside Studio:
- **Material Generator**: in the Toolbox, search "Material Generator" → describe a tiling material → get back PBR maps you can apply to any part. Best for floors, walls, terrain, ground.
- **Texture Generator**: targets a specific UV layout on a specific mesh. Best for hero props that need bespoke texturing.

## Animations

Two paths:

### Path 1: Roblox's Animation Editor (in Studio)

For simple animations on rigs that already exist in Studio. Plugin → Animation Editor → select rig → keyframe. Save as KeyframeSequence, upload to Roblox to get an `AnimationId`.

### Path 2: Blender → FBX with bone animation

Animate in Blender on the same rig used for the mesh. Bake animation on export (settings above). In Studio, import via the Animation Editor or Animator plugin: load FBX → save as KeyframeSequence → upload.

For Roblox character animations specifically, the rig **must** match Roblox's `R15` skeleton (or `R6`). Use the Avatar Editor's "Rig Builder" to insert a reference rig, model around it, and animate using its bones.

### Animation Capture (Roblox-native)

Studio has a feature where you can record face/body motion from a webcam and turn it into a Roblox animation. Useful for cutscenes and NPC personality animations.

## Loading assets at runtime

Three ways to get an asset into a running game:

1. **Place it in Studio.** It ships with the place file. Standard for environment assets.
2. **`InsertService:LoadAsset(assetId)`** — server-side, returns a Model. Good for content that's stored as a published model. Limited by the moderation status of the asset.
3. **`MarketplaceService:LoadAsset(assetId)`** — for assets you own. Handles ownership checks.

For audio assets: just set the `SoundId` of a `Sound` instance to `rbxassetid://12345678`. Roblox streams it.

## The 2026 generative-AI workflow

The pattern that's working for shipping creators:

1. **Block out the level in Studio with default parts.** Walls, floors, rough placement. Use Roblox's terrain editor for outdoor environments.
2. **Generate placeholder props with Cube** to populate the scene. Get the playtest experience right before investing in art.
3. **Hand-model or commission hero assets in Blender.** Replace Cube placeholders one by one as the game gets closer to ship.
4. **Use Material Generator for ambient surfaces** (rock walls, wood floors, fabric).
5. **Use Procedural Models for repeatable architecture** (buildings, fences, modular dungeons).

Don't try to ship raw Cube output as your final art. Cube is for getting unstuck fast, not for hitting a polished bar.

## Reading list

- Official Blender → Roblox guide: `https://create.roblox.com/docs/art/modeling/blender`
- Cube 3D announcement: `https://about.roblox.com/newsroom/2025/03/introducing-roblox-cube`
- Procedural Models DevForum thread: search "Introducing Procedural Models"
- Tripo3D Roblox export guide: `https://www.tripo3d.ai/blog/export-ai-3d-model-to-roblox`
- Avatar Auto-Setup docs: `https://create.roblox.com/docs/avatar/auto-setup`
- FBX import limitations: `https://create.roblox.com/docs/art/modeling/3d-importer`
