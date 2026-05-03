--!strict
-- Dragon Warz deploy script.
-- Run with: lune run scripts/deploy.luau [--saved | --published]
--
-- What it does:
--   1. Reads PLACE_ID + UNIVERSE_ID from deploy.config.json (or env vars)
--   2. Reads ROBLOX_API_KEY from env (set in your shell or .env)
--   3. Runs `rojo build default.project.json -o build/dragon-warz.rbxlx`
--   4. PATCHes the built place file to Roblox via Open Cloud
--      Place Publishing API. By default uses versionType=Saved (visible to
--      you only); pass --published to push live to all players.
--
-- Why one script and not a Bash + Lune split: Lune ships with `net`, `fs`,
-- and `process` — everything we need. One file = one source of truth, no
-- shell-syntax cross-platform headaches (Windows/macOS/Linux all run it
-- identically). The user runs Lune already (it's in rokit.toml).
--
-- Auth: Roblox API keys are sensitive. .env is gitignored. The
-- key needs the `universes.places:write` scope. Restrict to your own IP
-- in the Roblox dashboard for safety.

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")

-- ============================================================================
-- CONFIG LOADING
-- ============================================================================

-- Load deploy.config.json if present. Falls back to env vars so CI doesn't
-- need a config file checked into the repo.
local function loadConfig(): { placeId: string, universeId: string }
	local placeId: string? = process.env.PLACE_ID
	local universeId: string? = process.env.UNIVERSE_ID

	if fs.isFile("deploy.config.json") then
		local raw = fs.readFile("deploy.config.json")
		local parsed = net.jsonDecode(raw)
		placeId = placeId or parsed.placeId
		universeId = universeId or parsed.universeId
	end

	-- Also load .env file if it exists. Lune doesn't auto-load it like Node.
	if fs.isFile(".env") then
		local raw = fs.readFile(".env")
		for line in raw:gmatch("[^\r\n]+") do
			local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
			if trimmed ~= "" and not trimmed:match("^#") then
				local key, value = trimmed:match("^([^=]+)=(.+)$")
				if key and value then
					-- Strip surrounding quotes if present
					value = value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
					if not process.env[key] then
						process.env[key] = value
					end
				end
			end
		end
		-- Re-read after .env loaded
		placeId = placeId or process.env.PLACE_ID
		universeId = universeId or process.env.UNIVERSE_ID
	end

	if not placeId or not universeId then
		error([[
Missing PLACE_ID or UNIVERSE_ID. Set them via either:
  - deploy.config.json (gitignored): {"placeId": "...", "universeId": "..."}
  - Environment variables PLACE_ID, UNIVERSE_ID
  - .env file with PLACE_ID=... UNIVERSE_ID=... lines

Find these IDs in Creator Hub:
  Universe ID: https://create.roblox.com/dashboard/creations → click experience → URL contains /universes/{ID}
  Place ID: same page, "Places" panel → URL of the place itself
]])
	end

	return { placeId = placeId :: string, universeId = universeId :: string }
end

-- ============================================================================
-- CLI ARG PARSING
-- ============================================================================

-- Default to Saved (visible only to you). --published flag goes live for all.
-- We default to Saved as a safety: a typo or bad commit shouldn't auto-ship
-- to players. CI workflow that wants prod publishes passes --published.
local versionType: "Saved" | "Published" = "Saved"
for _, arg in process.args do
	if arg == "--published" or arg == "--prod" then
		versionType = "Published"
	elseif arg == "--saved" then
		versionType = "Saved"
	end
end

print(`[deploy] versionType={versionType}`)

-- ============================================================================
-- BUILD STEP
-- ============================================================================

local config = loadConfig()
local apiKey = process.env.ROBLOX_API_KEY
if not apiKey then
	error("ROBLOX_API_KEY not set. Add to .env or export in your shell.")
end

print(`[deploy] Building place via rojo...`)

-- Ensure build dir exists. Lune's fs.writeDir is recursive.
if not fs.isDir("build") then
	fs.writeDir("build")
end

local buildOutput = "build/dragon-warz.rbxlx"
local rojoResult = process.spawn("rojo", { "build", "default.project.json", "-o", buildOutput })
if not rojoResult.ok then
	print("[deploy] Rojo build failed:")
	print(rojoResult.stderr)
	process.exit(1)
end
print(`[deploy] Built {buildOutput}`)

-- Verify the file actually exists and is non-empty (defensive — rojo might
-- exit 0 but produce nothing if the project file is bad)
if not fs.isFile(buildOutput) then
	error(`Build output {buildOutput} not found after rojo build`)
end
local placeBytes = fs.readFile(buildOutput)
if #placeBytes < 1000 then
	error(`Build output suspiciously small ({#placeBytes} bytes). Aborting.`)
end
print(`[deploy] Place size: {#placeBytes} bytes`)

-- ============================================================================
-- DEPLOY STEP — Open Cloud Place Publishing API
-- ============================================================================

local url = `https://apis.roblox.com/universes/v1/{config.universeId}/places/{config.placeId}/versions?versionType={versionType}`

print(`[deploy] POST {url}`)

local response = net.request({
	url = url,
	method = "POST",
	headers = {
		["x-api-key"] = apiKey,
		-- .rbxlx is XML; the Open Cloud spec wants octet-stream for the binary
		-- form (.rbxl) and either application/xml or octet-stream for XML.
		-- Using octet-stream works for both since Roblox sniffs the content.
		["Content-Type"] = "application/octet-stream",
	},
	body = placeBytes,
})

if not response.ok then
	print(`[deploy] FAILED: HTTP {response.statusCode} {response.statusMessage}`)
	print(response.body)
	process.exit(1)
end

print(`[deploy] HTTP {response.statusCode} — published successfully`)
print(response.body)

if versionType == "Saved" then
	print("[deploy] ✓ Saved to your Studio — open the place in Creator Hub to test.")
	print("[deploy]   Run with --published to push live to all players.")
else
	print("[deploy] ✓ Published live. Players will get the new version on next join.")
end
