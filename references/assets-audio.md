# Audio (including ElevenLabs → Roblox voice pipeline)

Audio in Roblox is straightforward: every sound is an asset with a numeric ID, played by a `Sound` instance. The interesting question is *where the audio comes from* — and for AI-generated voiceover, the answer is ElevenLabs (or similar TTS) → MP3 → Open Cloud upload → in-game `AudioId`.

## The mental model

Roblox doesn't run external WebSockets in published places, and even where `HttpService` works, the engine doesn't accept arbitrary streamed audio bytes — it needs an asset ID. So **all generative audio must be uploaded to Roblox first**. There's no way to live-stream ElevenLabs TTS into a running Roblox session. Generate offline, upload, play the AssetId.

This means voiceover has a build step. Treat it like a build step (a Lune or Node script in `scripts/voiceover/`) and you'll save yourself a lot of pain.

## ElevenLabs API quick reference

`https://elevenlabs.io/docs/api-reference`. Key model IDs as of 2026:

- `eleven_v3` — broadest language coverage (70+), most expressive. Use for cinematic NPC voiceover.
- `eleven_multilingual_v2` — high-quality multilingual narration. Good default.
- `eleven_flash_v2_5` — ultra-low latency (~75ms), optimized for streaming/real-time. **Not relevant for Roblox** (no real-time audio in-game), but useful if you ever drive a game off a separate Node service.

Voices: any voice ID from your library, including instant clones (a few seconds of source audio) and professional clones (high fidelity, requires more source material). Default Rachel: `21m00Tcm4TlvDq8ikWAM`.

Pricing model: 1 credit per character of input text for TTS. Other ops (STT, dubbing, music) are credit-per-second-of-audio. Credits reset monthly, roll over up to two months.

### Minimal TTS request

```bash
curl -X POST "https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}" \
  -H "xi-api-key: ${ELEVEN_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Welcome, traveler. The path ahead is dark.",
    "model_id": "eleven_multilingual_v2",
    "voice_settings": {
      "stability": 0.5,
      "similarity_boost": 0.75,
      "style": 0.3,
      "use_speaker_boost": true
    }
  }' \
  --output line.mp3
```

For batch generation across many lines (the realistic case for a Roblox game), use the Python or TypeScript SDK — official, both maintained.

```python
# scripts/voiceover/generate.py
import os
import json
from elevenlabs.client import ElevenLabs

client = ElevenLabs(api_key=os.environ["ELEVEN_API_KEY"])

with open("voiceover/lines.json") as f:
    lines = json.load(f)
# lines.json: { "shopkeeper_greeting_1": { "voice_id": "...", "text": "..." }, ... }

for line_id, line in lines.items():
    audio = client.text_to_speech.convert(
        voice_id=line["voice_id"],
        model_id="eleven_multilingual_v2",
        text=line["text"],
    )
    with open(f"voiceover/out/{line_id}.mp3", "wb") as out:
        for chunk in audio:
            out.write(chunk)
```

Keep `lines.json` in git. The MP3 output is gitignored (regenerable from the script).

### Audio tags and emotional control

ElevenLabs supports inline tags like `[whispers]`, `[sarcastically]`, `[giggles]` that influence delivery. Use them for personality:

```
"text": "[whispers] Don't tell the others, but I think the bridge is unstable. [sighs] We have to cross anyway."
```

Tags vary by model; v3 has the broadest support.

## ElevenLabs MCP server

There's an official ElevenLabs MCP server. Add it to Claude Code so the agent can drive TTS generation directly without you scripting it manually:

```bash
claude mcp add elevenlabs -- npx -y @elevenlabs/mcp-server
# (set ELEVEN_API_KEY in your env)
```

Useful when you're iterating on dialogue and want Claude to regenerate lines after edits without you running a separate script.

## Open Cloud → Roblox audio upload

After generating MP3s, upload them as Roblox `Audio` assets via the Open Cloud Assets API. Each upload returns an asset ID; that ID becomes `rbxassetid://...` in-game.

```bash
curl -X POST "https://apis.roblox.com/assets/v1/assets" \
  -H "x-api-key: ${ROBLOX_API_KEY}" \
  -F 'request={"assetType":"Audio","displayName":"shopkeeper_greeting_1","description":"Greeting line","creationContext":{"creator":{"userId":"123456"}}}' \
  -F "fileContent=@voiceover/out/shopkeeper_greeting_1.mp3"
```

Response: an operation ID. Poll `apis.roblox.com/assets/v1/operations/{operationId}` until `done: true`. The completed operation contains the asset ID.

**Critical**: the audio asset's audibility scope is restricted. By default, audio uploaded under your user ID is only playable in *your* experiences. To use audio in a group's game, upload under the group's API key.

### Glue script

A Lune (or Node, or Python) script that:

1. Reads `voiceover/lines.json` for line IDs and text.
2. For each line, generates MP3 via ElevenLabs.
3. Uploads MP3 to Roblox via Open Cloud, gets the asset ID.
4. Writes a Luau module mapping line IDs to asset IDs:

```luau
-- src/shared/Voiceover/Lines.luau (auto-generated)
return {
    shopkeeper_greeting_1 = "rbxassetid://12345678",
    shopkeeper_farewell_1 = "rbxassetid://12345679",
    -- ...
}
```

The game then `require`s this module and plays lines by ID:

```luau
local Lines = require(ReplicatedStorage.Shared.Voiceover.Lines)
local SoundService = game:GetService("SoundService")

local function play(lineId: string)
    local sound = Instance.new("Sound")
    sound.SoundId = Lines[lineId]
    sound.Parent = SoundService
    sound:Play()
    sound.Ended:Connect(function() sound:Destroy() end)
end

play("shopkeeper_greeting_1")
```

## Music

Same pipeline conceptually:

1. Generate or license music. ElevenLabs has a Music API (text → music). Suno, Udio, Boomy are alternatives. Or use licensed stock libraries (`audiio`, `epidemicsound`).
2. Upload as Audio asset via Open Cloud (same endpoint, same flow).
3. Use a `Sound` instance, often parented to `SoundService` for ambient looping.

For ambient music, consider Roblox's built-in audio system rather than playing a file in a Sound instance — `Soundscape` and the spatial audio API give richer behavior (occlusion, distance attenuation).

Music generation services have stricter commercial licensing than ElevenLabs TTS. Read the terms before shipping.

## SFX

Two routes:

1. **ElevenLabs Sound Effects API** — text → sound effect (`https://elevenlabs.io/sound-effects`). Great for unusual or specific cues ("metallic clink with a deep reverb tail"). Same upload pipeline.
2. **Roblox Creator Store / community SFX libraries** — many free SFX assets already on Roblox. Search the Toolbox.

## In-game spatial audio

Position-aware audio in Roblox: parent a `Sound` to a `BasePart`, set `Sound.SoundGroup`, set `EmitterSize` and `RollOffMaxDistance`. Roblox handles attenuation automatically.

The newer audio API (`AudioPlayer`, `AudioEmitter`, `AudioListener`, `AudioFader`, etc.) gives you a node-graph-based audio engine — more control over routing, mixing, effects. Worth learning for any project where audio quality matters.

## Lip sync

Roblox has built-in **dynamic head animation** that approximates lip-sync from any audio playback on a character's `Head` part — automatically, no extra setup. Quality is reasonable for casual speech.

For higher-quality lip-sync (specific phoneme timing), pre-process the audio: ElevenLabs has a Forced Alignment API that returns word-level (and phoneme-level if you push it) timestamps. Pipe those through a phoneme-to-viseme map and key the character's mouth blendshapes — this is custom work, not Roblox-native.

## In-experience voice chat (player-to-player, not generative)

Roblox has built-in **Spatial Voice** for live player-to-player voice chat. Different domain entirely from generated voiceover — players speak through their mics, the engine streams it spatially. Enable in `VoiceChatService`. Subject to age verification and safety constraints.

Don't confuse this with TTS NPCs. Spatial Voice is for human players talking to each other; ElevenLabs is for AI-generated NPC speech.

## Common gotchas

- **`HttpService` can't reach `api.elevenlabs.io` from a published place** unless you've enabled HTTP requests for that universe in Game Settings. Even then, you'd be hitting ElevenLabs from inside the game, which is a *very* different architectural choice (latency, rate limits, key exposure, cost) than the upload-once pipeline. Default to upload pipeline; only call ElevenLabs at runtime if you have a strong reason (dynamic NPC dialogue from player chat, for example).
- **Audio asset audibility**. Audio uploaded to your user is only audible in *your* experiences (or experiences you've explicitly granted). For group games, upload under the group's API key.
- **Rate limits on uploads.** Don't try to upload 10,000 lines in a tight loop. Throttle to ~10/sec or use the bulk upload patterns Roblox documents.
- **Audio asset moderation.** Uploaded audio goes through Roblox moderation. If it fails, the asset is unusable. For any generated content, manually preview before bulk-uploading; flagged audio costs you ElevenLabs credits with no Roblox payoff.

## Reading list

- ElevenLabs API: `https://elevenlabs.io/docs/api-reference`
- ElevenLabs models cheat sheet: `https://www.webfuse.com/elevenlabs-cheat-sheet`
- ElevenLabs MCP server: search npm `@elevenlabs/mcp-server`
- Roblox Open Cloud Assets: `https://create.roblox.com/docs/cloud/features/assets-api`
- Roblox audio system: `https://create.roblox.com/docs/sound/dynamic-effects`
- Spatial Voice: `https://create.roblox.com/docs/chat/voice-chat`
