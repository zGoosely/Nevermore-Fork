--!strict
--[=[
	Attribute names used by game configurations.

	@class GameConfigConstants
]=]

const require = require("../../../../Loader").load()

const TableUtils = require("TableUtils")

return TableUtils.readonly({
	GAME_ID_ATTRIBUTE = "GameId",
})
