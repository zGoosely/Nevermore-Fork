--!strict
--[=[
	Defaults for the optional PlayerInput cooldown integration.

	@class PlayerInputCooldownServiceConstants
]=]
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly({
	DEFAULT_RESTRICTION_PRIORITY = 1_000_000,
})
