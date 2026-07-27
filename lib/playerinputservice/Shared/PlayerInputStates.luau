--!strict
--[=[
	Input lifecycle states emitted by PlayerInputService.

	@class PlayerInputStates
]=]

const require = require("../../Loader").load()

const TableUtils = require("TableUtils")

return TableUtils.deepReadonly({
	BEGIN = "Begin" :: "Begin",
	END = "End" :: "End",
	CANCEL = "Cancel" :: "Cancel",
})
