--!strict
--[=[
	Utility functions to provide/configure a permission. See [BasePermissionProvider] and [PermissionService].

	@server
	@util PermissionProviderUtils
]=]

const require = require("../../Loader").load()

const PermissionProviderConstants = require("PermissionProviderConstants")

const PermissionProviderUtils = {}

--> Types

type GroupRankConfigInput = {
	groupId: number,
	minAdminRequiredRank: number,
	minCreatorRequiredRank: number,
}

export type GroupRankConfig = {
	type: "GroupRankConfigType",
} & GroupRankConfigInput

type SingleUserConfigInput = {
	userId: number,
}

export type SingleUserConfig = {
	type: "SingleUserConfigType",
} & SingleUserConfigInput

export type PermissionProviderConfig = GroupRankConfig | SingleUserConfig

--> Constants

const DEFAULT_MIN_ADMIN_RANK = 250
const DEFAULT_MIN_CREATOR_RANK = 254

--[=[
	Creates a group rank config

	@within PermissionProviderUtils
	@param config { groupId: number, minAdminRequiredRank: number, minCreatorRequiredRank: number }
	@return GroupRankConfig
]=]
function PermissionProviderUtils.createGroupRankConfig(config: GroupRankConfigInput): GroupRankConfig
	assert(type(config.groupId) == "number", "Bad groupId")
	assert(type(config.minAdminRequiredRank) == "number", "Bad minAdminRequiredRank")
	assert(type(config.minCreatorRequiredRank) == "number", "Bad minCreatorRequiredRank")

	return {
		type = PermissionProviderConstants.GROUP_RANK_CONFIG_TYPE,
		groupId = config.groupId,
		minAdminRequiredRank = config.minAdminRequiredRank,
		minCreatorRequiredRank = config.minCreatorRequiredRank,
	}
end

--[=[
	Creates a single user config

	@within PermissionProviderUtils
	@param config { userId: number }
	@return SingleUserConfig
]=]
function PermissionProviderUtils.createSingleUserConfig(config: SingleUserConfigInput): SingleUserConfig
	assert(type(config.userId) == "number", "Bad userId")

	return {
		type = PermissionProviderConstants.SINGLE_USER_CONFIG_TYPE,
		userId = config.userId,
	}
end

--[=[
	Creates a configuration from the game's creator: a group rank config for
	group-owned games, a single user config otherwise.

	@within PermissionProviderUtils
	@return PermissionProviderConfig
]=]
function PermissionProviderUtils.createConfigFromGame(): PermissionProviderConfig
	if game.CreatorType == Enum.CreatorType.Group then
		return PermissionProviderUtils.createGroupRankConfig({
			groupId = game.CreatorId,
			minAdminRequiredRank = DEFAULT_MIN_ADMIN_RANK,
			minCreatorRequiredRank = DEFAULT_MIN_CREATOR_RANK,
		})
	end

	return PermissionProviderUtils.createSingleUserConfig({
		userId = game.CreatorId,
	})
end

return PermissionProviderUtils
