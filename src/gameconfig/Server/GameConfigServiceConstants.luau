--!strict
--[=[
	Constants used by GameConfigService.

	@class GameConfigServiceConstants
]=]

const require = require("../../Loader").load()

const TableUtils = require("TableUtils")

return TableUtils.readonly({
	DEFAULT_CONFIG_NAME = "DefaultGameConfig",
	CONFIG_CONTAINER_NAME = "GameConfigs",
})
