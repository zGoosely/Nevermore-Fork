--!strict
--[=[
	Shared attribute names, binder tag, and defaults for CooldownService.

	@class CooldownServiceConstants
]=]
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly({
	TAG_NAME = "Cooldown",
	KEY_ATTRIBUTE = "CooldownKey",
	STARTED_AT_ATTRIBUTE = "CooldownStartedAt",
	ENDS_AT_ATTRIBUTE = "CooldownEndsAt",
	PREDICTED_ATTRIBUTE = "CooldownPredicted",
	FOLDER_NAME_PREFIX = "Cooldown_",
})
