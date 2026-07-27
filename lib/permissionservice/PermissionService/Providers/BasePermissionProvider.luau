--!strict
--[=[
	Basic interface for providing permissions.

	Providers only answer questions -- [PermissionService] owns the networking
	and decides what reaches the client.

	@server
	@class BasePermissionProvider
]=]

const require = require("../../../Loader").load()

const BaseObject = require("BaseObject")
const Promise = require("Promise")
const TableUtils = require("TableUtils")
const PermissionLevel = require("PermissionLevel")
const PermissionProviderUtils = require("PermissionProviderUtils")

const BasePermissionProvider = setmetatable({}, BaseObject)
BasePermissionProvider.ClassName = "BasePermissionProvider"
BasePermissionProvider.__index = BasePermissionProvider

export type BasePermissionProvider =
	typeof(setmetatable(
		{} :: {
			_config: PermissionProviderUtils.PermissionProviderConfig,
		},
		{} :: typeof({ __index = BasePermissionProvider })
	))
	& BaseObject.BaseObject<any>

--[=[
	Initializes a new permission provider

	@within BasePermissionProvider
	@param config PermissionProviderConfig
	@return BasePermissionProvider
]=]
function BasePermissionProvider.new(config: PermissionProviderUtils.PermissionProviderConfig): BasePermissionProvider
	const self: BasePermissionProvider = setmetatable(BaseObject.new() :: any, BasePermissionProvider)

	self._config = TableUtils.readonly(assert(config, "Bad config") :: any)

	return self
end

--[=[
	Starts the permission provider. Should be done via [PermissionService].

	@within BasePermissionProvider
]=]
function BasePermissionProvider.Start(_self: BasePermissionProvider): () end

--[=[
	Returns whether the player holds a permission level.

	@within BasePermissionProvider
	@param player Player
	@param permissionLevel PermissionLevel
	@return Promise<boolean>
]=]
function BasePermissionProvider.PromiseIsPermissionLevel(
	_self: BasePermissionProvider,
	player: Player,
	permissionLevel: PermissionLevel.PermissionLevelType
): Promise.Promise<boolean>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(PermissionLevel:IsValue(permissionLevel), "Bad permissionLevel")

	error("Not implemented")
end

--[=[
	Returns whether the player is an admin.

	@within BasePermissionProvider
	@param player Player
	@return Promise<boolean>
]=]
function BasePermissionProvider.PromiseIsAdmin(self: BasePermissionProvider, player: Player): Promise.Promise<boolean>
	return self:PromiseIsPermissionLevel(player, PermissionLevel.ADMIN)
end

--[=[
	Returns whether the player is a creator.

	@within BasePermissionProvider
	@param player Player
	@return Promise<boolean>
]=]
function BasePermissionProvider.PromiseIsCreator(self: BasePermissionProvider, player: Player): Promise.Promise<boolean>
	return self:PromiseIsPermissionLevel(player, PermissionLevel.CREATOR)
end

--[=[
	Returns whether the player holds a permission level.

	:::info
	Returns false rather than yielding if the answer has not loaded yet. Prefer
	[BasePermissionProvider.PromiseIsPermissionLevel].
	:::

	@within BasePermissionProvider
	@param player Player
	@param permissionLevel PermissionLevel
	@return boolean
]=]
function BasePermissionProvider.IsPermissionLevel(
	self: BasePermissionProvider,
	player: Player,
	permissionLevel: PermissionLevel.PermissionLevelType
): boolean
	const promise = self:PromiseIsPermissionLevel(player, permissionLevel)
	if promise:IsPending() then
		return false
	end

	const success, result = promise:Yield()
	if not success then
		warn(`[BasePermissionProvider] - {result}`)
		return false
	end

	return result == true
end

--[=[
	Returns whether the player is an admin, without yielding.

	@within BasePermissionProvider
	@param player Player
	@return boolean
]=]
function BasePermissionProvider.IsAdmin(self: BasePermissionProvider, player: Player): boolean
	return self:IsPermissionLevel(player, PermissionLevel.ADMIN)
end

--[=[
	Returns whether the player is a creator, without yielding.

	@within BasePermissionProvider
	@param player Player
	@return boolean
]=]
function BasePermissionProvider.IsCreator(self: BasePermissionProvider, player: Player): boolean
	return self:IsPermissionLevel(player, PermissionLevel.CREATOR)
end

return BasePermissionProvider
