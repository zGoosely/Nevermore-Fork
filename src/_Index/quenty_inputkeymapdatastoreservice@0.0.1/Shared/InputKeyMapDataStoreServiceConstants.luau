--!strict
--[=[
	Constants for persisted input-keymap bindings and their network protocol.

	@class InputKeyMapDataStoreServiceConstants
]=]
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly({
	MAX_BINDINGS = 256,
	MAX_INPUT_TYPES = 8,
	MAX_MODIFIERS = 4,
	MAX_NAME_LENGTH = 64,
	MAX_SERIALIZED_INPUT_NAME_LENGTH = 128,
	PROFILE_PATH = "InputKeyMapBindings",
	RATE_LIMIT_CAPACITY = 20,
	RATE_LIMIT_REFILL_RATE = 10,
	SERIALIZED_KEY_CODE = 0,
	SERIALIZED_USER_INPUT_TYPE = 1,
	SERIALIZED_VIRTUAL_INPUT = 2,
	SERIALIZED_MODIFIER_CHORD = 3,
	SERIALIZED_SLOTTED_TOUCH_BUTTON = 4,
})
