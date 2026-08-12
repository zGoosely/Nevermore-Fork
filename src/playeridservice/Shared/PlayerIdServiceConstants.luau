--!strict
--[=[
	Shared constants for PlayerIdService.

	@class PlayerIdServiceConstants
]=]

const require = require("../../Loader").load()

return require("TableUtils").deepReadonly({
	PLAYER_ID_ATTRIBUTE = "NevermorePlayerId",
	MIN_PLAYER_ID = 1,
	MAX_PLAYER_ID = 255,
})
