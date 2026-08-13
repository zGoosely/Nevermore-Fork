--!strict
--[=[
	Protocol and policy constants for PlayerInputService.

	@class PlayerInputServiceConstants
]=]
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly({
	DEFAULT_CONTEXT_NAME = "Default",
	DEFAULT_CONTEXT_PRIORITY = 0,
	DEFAULT_GLOBAL_RATE_LIMIT_CAPACITY = 60,
	DEFAULT_GLOBAL_RATE_LIMIT_REFILL_RATE = 30,
	MAX_ACTION_ID = 65535,
	MIN_ACTION_ID = 0,
	NETWORK_STATE_BEGIN = 0,
	NETWORK_STATE_END = 1,
	NETWORK_STATE_CANCEL = 2,
	SERIALIZED_KEY_CODE = 0,
	SERIALIZED_USER_INPUT_TYPE = 1,
	SERIALIZED_VIRTUAL_INPUT = 2,
	SERIALIZED_MODIFIER_CHORD = 3,
	SERIALIZED_SLOTTED_TOUCH_BUTTON = 4,
})
