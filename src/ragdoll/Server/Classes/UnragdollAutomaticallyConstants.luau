--!strict
--[=[
	@class UnragdollAutomaticallyConstants
]=]

const require = require("../../../Loader").load()

local TableUtils = require("TableUtils")

return TableUtils.readonly({
	UNRAGDOLL_AUTOMATICALLY_ATTRIBUTE = "UnragdollAutomatically",
	UNRAGDOLL_AUTOMATIC_TIME_ATTRIBUTE = "UnragdollAutomaticTime",
})
