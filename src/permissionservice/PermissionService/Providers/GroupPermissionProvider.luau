--!strict
--[=[
	Provides permissions from a group

	@server
	@class GroupPermissionProvider
]=]

const Players = game:GetService("Players")

const require = require("../../../Loader").load()

const Promise = require("Promise")
const GroupUtils = require("GroupUtils")
const BasePermissionProvider = require("BasePermissionProvider")
const PermissionLevel = require("PermissionLevel")
const PermissionProviderConstants = require("PermissionProviderConstants")
const PermissionProviderUtils = require("PermissionProviderUtils")

const GroupPermissionProvider = setmetatable({}, BasePermissionProvider)
GroupPermissionProvider.ClassName = "GroupPermissionProvider"
GroupPermissionProvider.__index = GroupPermissionProvider

export type GroupPermissionProvider =
	typeof(setmetatable(
		{} :: {
			_config: PermissionProviderUtils.GroupRankConfig,
			_rankPromises: { [number]: Promise.Promise<number> },
		},
		{} :: typeof({ __index = GroupPermissionProvider })
	))
	& BasePermissionProvider.BasePermissionProvider

--[=[
	@within GroupPermissionProvider
	@param config GroupRankConfig
	@return GroupPermissionProvider
]=]
function GroupPermissionProvider.new(config: PermissionProviderUtils.GroupRankConfig): GroupPermissionProvider
	const self: GroupPermissionProvider =
		setmetatable(BasePermissionProvider.new(config) :: any, GroupPermissionProvider)

	assert(self._config.type == PermissionProviderConstants.GROUP_RANK_CONFIG_TYPE, "Bad configType")

	self._rankPromises = {}

	return self
end

--[=[
	Starts the permission provider. Should be done via [PermissionService].

	@within GroupPermissionProvider
]=]
function GroupPermissionProvider.Start(self: GroupPermissionProvider)
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player: Player)
		self._rankPromises[player.UserId] = nil
	end))
end

--[=[
	Returns whether the player holds a permission level, by comparing their group
	rank against the configured minimum for that level.

	@within GroupPermissionProvider
	@param player Player
	@param permissionLevel PermissionLevel
	@return Promise<boolean>
]=]
function GroupPermissionProvider.PromiseIsPermissionLevel(
	self: GroupPermissionProvider,
	player: Player,
	permissionLevel: PermissionLevel.PermissionLevelType
): Promise.Promise<boolean>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(PermissionLevel:IsValue(permissionLevel), "Bad permissionLevel")

	const requiredRank = if permissionLevel == PermissionLevel.CREATOR
		then self._config.minCreatorRequiredRank
		else self._config.minAdminRequiredRank

	return self:_promiseRankInGroup(player):Then(function(rank: number)
		return rank >= requiredRank
	end)
end

function GroupPermissionProvider._promiseRankInGroup(
	self: GroupPermissionProvider,
	player: Player
): Promise.Promise<number>
	const userId = player.UserId

	-- Cached per player: the rank is fetched once and every permission question
	-- for that player is answered from it
	if not self._rankPromises[userId] then
		self._rankPromises[userId] = GroupUtils.promiseRankInGroup(player, self._config.groupId)
	end

	return self._rankPromises[userId]
end

return GroupPermissionProvider
