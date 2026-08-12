--!strict
--[=[
	Provides permissions from a single user creator

	@server
	@class CreatorPermissionProvider
]=]

const RunService = game:GetService("RunService")

const require = require("../../../Loader").load()

const Promise = require("Promise")
const BasePermissionProvider = require("BasePermissionProvider")
const PermissionLevel = require("PermissionLevel")
const PermissionProviderConstants = require("PermissionProviderConstants")
const PermissionProviderUtils = require("PermissionProviderUtils")

const CreatorPermissionProvider = setmetatable({}, BasePermissionProvider)
CreatorPermissionProvider.ClassName = "CreatorPermissionProvider"
CreatorPermissionProvider.__index = CreatorPermissionProvider

export type CreatorPermissionProvider =
	typeof(setmetatable(
		{} :: {
			_config: PermissionProviderUtils.SingleUserConfig,
			_userId: number,
		},
		{} :: typeof({ __index = CreatorPermissionProvider })
	))
	& BasePermissionProvider.BasePermissionProvider

--[=[
	@within CreatorPermissionProvider
	@param config SingleUserConfig
	@return CreatorPermissionProvider
]=]
function CreatorPermissionProvider.new(config: PermissionProviderUtils.SingleUserConfig): CreatorPermissionProvider
	const self: CreatorPermissionProvider =
		setmetatable(BasePermissionProvider.new(config) :: any, CreatorPermissionProvider)

	assert(self._config.type == PermissionProviderConstants.SINGLE_USER_CONFIG_TYPE, "Bad configType")
	self._userId = assert(self._config.userId, "No userId")

	return self
end

--[=[
	Returns whether the player holds a permission level. The creator holds every
	level, as does anyone testing in Studio.

	@within CreatorPermissionProvider
	@param player Player
	@param permissionLevel PermissionLevel
	@return Promise<boolean>
]=]
function CreatorPermissionProvider.PromiseIsPermissionLevel(
	self: CreatorPermissionProvider,
	player: Player,
	permissionLevel: PermissionLevel.PermissionLevelType
): Promise.Promise<boolean>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(PermissionLevel:IsValue(permissionLevel), "Bad permissionLevel")

	return Promise.resolved(player.UserId == self._userId or RunService:IsStudio())
end

return CreatorPermissionProvider
