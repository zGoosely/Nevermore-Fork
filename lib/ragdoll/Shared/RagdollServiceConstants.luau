--!strict
--[=[
	@class RagdollServiceConstants
]=]

const require = require("../../Loader").load()

local TableUtils = require("TableUtils")

return TableUtils.readonly({
	SCREEN_SHAKE_ENABLED_ATTRIBUTE = "RagdollScreenShakeEnabled",
})
