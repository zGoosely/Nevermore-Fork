--!strict
--[=[
	Shared constants for PlayerIdService.

	@class PlayerIdServiceConstants
]=]
return require("@game/ReplicatedStorage/Packages/TableUtils").deepReadonly({
	PLAYER_ID_ATTRIBUTE = "NevermorePlayerId",
	MIN_PLAYER_ID = 1,
	MAX_PLAYER_ID = 255,
})
