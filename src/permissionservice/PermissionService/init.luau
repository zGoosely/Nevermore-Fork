--!strict
--[=[
	Provides permissions for the game. See [BasePermissionProvider].

	Permissions are static: they come from the configured provider (game group
	rank, or the creator's user id) and are resolved once per player as they
	join, then pushed to that player over [PermissionServiceNetwork].

	:::tip
	Be sure to initialize the [PermissionServiceClient] on the client.
	:::

	@server
	@class PermissionService
]=]

const Players = game:GetService("Players")

const require = require("../Loader").load()

const Maid = require("Maid")
const ServiceBag = require("ServiceBag")
const Promise = require("Promise")
const Brio = require("Brio")
const Observable = require("Observable")
const Rx = require("Rx")
const RxBrioUtils = require("RxBrioUtils")
const RxPlayerUtils = require("RxPlayerUtils")
const BasePermissionProvider = require("BasePermissionProvider")
const CreatorPermissionProvider = require("CreatorPermissionProvider")
const GroupPermissionProvider = require("GroupPermissionProvider")
const PermissionLevel = require("PermissionLevel")
const PermissionProviderConstants = require("PermissionProviderConstants")
const PermissionProviderUtils = require("PermissionProviderUtils")
const PermissionServiceNetwork = require("PermissionServiceNetwork")

const PermissionService = {}
PermissionService.ServiceName = "PermissionService"
PermissionService.ServerOnly = true

export type PermissionService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,

		_provider: BasePermissionProvider.BasePermissionProvider?,
		_providerPromise: Promise.Promise<BasePermissionProvider.BasePermissionProvider>,
	},
	{} :: typeof({ __index = PermissionService })
))

--[=[
	Initializes the service. Should be done via [ServiceBag].

	@within PermissionService
	@param serviceBag ServiceBag
]=]
function PermissionService.Init(self: PermissionService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	self._provider = nil
	self._providerPromise = self._maid:GivePromise(Promise.new())
end

function PermissionService.Start(self: PermissionService)
	if not self._provider then
		self:SetProviderFromConfig(PermissionProviderUtils.createConfigFromGame())
	end

	const provider = assert(self._provider, "No provider")
	provider:Start()
	self._providerPromise:Resolve(provider)

	self._maid:Add(RxPlayerUtils.observePlayersBrio():Subscribe(function(brio)
		const maid, player = brio:ToMaidAndValue()

		maid:GivePromise(self:PromiseIsAdmin(player))
			:Then(function(isAdmin: boolean)
				PermissionServiceNetwork.packets.permissionsLoaded.sendTo({
					isAdmin = isAdmin,
				}, player)
			end)
			:Catch(function(...): ...any
				warn(`[PermissionService] - Failed to resolve permissions for {player.UserId} ({...})`)
			end)
	end))

	-- The provider is already resolved by Start, so answer from its current state.
	PermissionServiceNetwork.queries.isAdmin.listen(function(value: { userId: number }): { isAdmin: boolean }
		return {
			isAdmin = self:IsAdmin(value.userId),
		}
	end)
end

--[=[
	Sets the provider from a config. See [PermissionProviderUtils.createGroupRankConfig]
	and [PermissionProviderUtils.createSingleUserConfig].

	@within PermissionService
	@param config PermissionProviderConfig
]=]
function PermissionService.SetProviderFromConfig(
	self: PermissionService,
	config: PermissionProviderUtils.PermissionProviderConfig
)
	assert(self._maid, "Not initialized")
	assert(not self._provider, "Already have provider set")

	if config.type == PermissionProviderConstants.GROUP_RANK_CONFIG_TYPE then
		self._provider = self._maid:Add(GroupPermissionProvider.new(config))
	elseif config.type == PermissionProviderConstants.SINGLE_USER_CONFIG_TYPE then
		self._provider = self._maid:Add(CreatorPermissionProvider.new(config))
	else
		error("Bad config")
	end
end

--[=[
	Returns the permission provider once [PermissionService.Start] has run.

	@within PermissionService
	@return Promise<BasePermissionProvider>
]=]
function PermissionService.PromisePermissionProvider(
	self: PermissionService
): Promise.Promise<BasePermissionProvider.BasePermissionProvider>
	return self._providerPromise
end

--[=[
	Returns whether the player is an admin.

	@within PermissionService
	@param player Player
	@return Promise<boolean>
]=]
function PermissionService.PromiseIsAdmin(self: PermissionService, player: Player): Promise.Promise<boolean>
	return self:PromiseIsPermissionLevel(player, PermissionLevel.ADMIN)
end

--[=[
	Returns whether the player is a creator.

	@within PermissionService
	@param player Player
	@return Promise<boolean>
]=]
function PermissionService.PromiseIsCreator(self: PermissionService, player: Player): Promise.Promise<boolean>
	return self:PromiseIsPermissionLevel(player, PermissionLevel.CREATOR)
end

--[=[
	Returns whether a user id belongs to an admin currently in the game.

	:::info
	Answers from what the provider has already resolved rather than yielding for
	it, so a user who is not in the game -- or whose permissions are still
	loading -- reads as false. Prefer [PermissionService.PromiseIsAdmin] unless
	you cannot yield.
	:::

	@within PermissionService
	@param userId number
	@return boolean
]=]
function PermissionService.IsAdmin(self: PermissionService, userId: number): boolean
	assert(type(userId) == "number", "Bad userId")

	const provider = self._provider
	if not provider then
		return false
	end

	const player = Players:GetPlayerByUserId(userId)
	if not player then
		return false
	end

	return provider:IsAdmin(player)
end

--[=[
	Returns whether the player holds a permission level.

	@within PermissionService
	@param player Player
	@param permissionLevel PermissionLevel
	@return Promise<boolean>
]=]
function PermissionService.PromiseIsPermissionLevel(
	self: PermissionService,
	player: Player,
	permissionLevel: PermissionLevel.PermissionLevelType
): Promise.Promise<boolean>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(PermissionLevel:IsValue(permissionLevel), "Bad permissionLevel")

	return self:PromisePermissionProvider():Then(function(provider)
		return provider:PromiseIsPermissionLevel(player, permissionLevel)
	end)
end

--[=[
	Observes every player holding a permission level.

	@within PermissionService
	@param permissionLevel PermissionLevel
	@return Observable<Brio<Player>>
]=]
function PermissionService.ObservePermissionedPlayersBrio(
	self: PermissionService,
	permissionLevel: PermissionLevel.PermissionLevelType
): Observable.Observable<Brio.Brio<Player>>
	assert(PermissionLevel:IsValue(permissionLevel), "Bad permissionLevel")

	return RxPlayerUtils.observePlayersBrio():Pipe({
		RxBrioUtils.flatMapBrio(function(player: Player)
			return Rx.fromPromise(self:PromiseIsPermissionLevel(player, permissionLevel)):Pipe({
				Rx.switchMap(function(hasPermission: boolean): any
					return if hasPermission then Rx.of(player) else Rx.EMPTY
				end) :: any,
			}) :: any
		end) :: any,
	}) :: any
end

function PermissionService.Destroy(self: PermissionService)
	self._maid:Destroy()
end

return PermissionService
