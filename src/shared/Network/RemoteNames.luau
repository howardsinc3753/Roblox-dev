--!strict
-- Canonical list of all remote event/function names.
-- Both server and client reference this to avoid string typos.

return {
	-- Client → Server (RemoteEvents)
	SelectDragon = "SelectDragon",
	UnlockDragon = "UnlockDragon",
	FireBreath = "FireBreath",
	UseSpecial = "UseSpecial",

	-- Server → Client (RemoteEvents)
	DamagePlayer = "DamagePlayer",
	PlayerKO = "PlayerKO",
	RoundStart = "RoundStart",
	RoundEnd = "RoundEnd",
	UpdateCoins = "UpdateCoins",
	SpawnDragon = "SpawnDragon",
	UpdateScoreboard = "UpdateScoreboard",

	-- Client → Server (RemoteFunctions)
	GetPlayerData = "GetPlayerData",
}
