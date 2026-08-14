--!strict
--[=[
	Input lifecycle states emitted by PlayerInputService.

	@class PlayerInputStates
]=]
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly({
	BEGIN = "Begin" :: "Begin",
	END = "End" :: "End",
	CANCEL = "Cancel" :: "Cancel",
})
