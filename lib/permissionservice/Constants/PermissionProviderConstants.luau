--!strict
--[=[
	Constants for the permission system

	@class PermissionProviderConstants
]=]

const require = require("../../Loader").load()

const TableUtils = require("TableUtils")

export type PermissionProviderConstants = {
	GROUP_RANK_CONFIG_TYPE: "GroupRankConfigType",
	SINGLE_USER_CONFIG_TYPE: "SingleUserConfigType",
}

return TableUtils.readonly({
	GROUP_RANK_CONFIG_TYPE = "GroupRankConfigType",
	SINGLE_USER_CONFIG_TYPE = "SingleUserConfigType",
} :: PermissionProviderConstants)
