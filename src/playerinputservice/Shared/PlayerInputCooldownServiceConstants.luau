--!strict
--[=[
	Defaults for the optional PlayerInput cooldown integration.

	@class PlayerInputCooldownServiceConstants
]=]

const require = require("../../Loader").load()

const TableUtils = require("TableUtils")

return TableUtils.deepReadonly({
	DEFAULT_RESTRICTION_PRIORITY = 1_000_000,
})
