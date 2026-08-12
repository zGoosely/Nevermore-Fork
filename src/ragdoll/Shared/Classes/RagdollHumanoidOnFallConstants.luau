--!strict
--[=[
	Constants for [RagdollHumanoidOnFall].
	@class RagdollHumanoidOnFallConstants
]=]

const require = require("../../../Loader").load()

local TableUtils = require("TableUtils")

return TableUtils.readonly({
	REMOTE_EVENT_NAME = "RagdollHumanoidOnFallRemoteEvent",
})
