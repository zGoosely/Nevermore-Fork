--!strict
--[=[
	Shared configuration for ServerRegionService.

	@constants ServerRegionServiceConstants
]=]

const require = require("../../Loader").load()

const TableUtils = require("TableUtils")

return TableUtils.deepReadonly({
	GEOLOCATION_URL = "https://ipconfig.io/json",
	MAX_REGION_LENGTH = 64,
	REGION_ATTRIBUTE = "ServerRegion",
})
