--!strict
--[=[
	Constants used by GameConfigService.

	@class GameConfigServiceConstants
]=]
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.readonly({
	DEFAULT_CONFIG_NAME = "DefaultGameConfig",
	CONFIG_CONTAINER_NAME = "GameConfigs",
})
