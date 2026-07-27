--!strict
--[=[
	Shared attribute names, binder tag, and defaults for CooldownService.

	@class CooldownServiceConstants
]=]

const require = require("../../Loader").load()

const TableUtils = require("TableUtils")

return TableUtils.deepReadonly({
	TAG_NAME = "Cooldown",
	KEY_ATTRIBUTE = "CooldownKey",
	STARTED_AT_ATTRIBUTE = "CooldownStartedAt",
	ENDS_AT_ATTRIBUTE = "CooldownEndsAt",
	PREDICTED_ATTRIBUTE = "CooldownPredicted",
	FOLDER_NAME_PREFIX = "Cooldown_",
})
