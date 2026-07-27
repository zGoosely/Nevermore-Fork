--!strict
--[=[
	Provides permissions on the client. See [PermissionService] for more details.

	Read-only: permissions are decided on the server and pushed down, so there is
	no setter here.

	:::tip
	Be sure to initialize the [PermissionService] on the server.
	:::

	@client
	@class PermissionServiceClient
]=]

const require = require("../Loader").load()

const Maid = require("Maid")
const ServiceBag = require("ServiceBag")
const Promise = require("Promise")
const Observable = require("Observable")
const PermissionProviderClient = require("PermissionProviderClient")

const PermissionServiceClient = {}
PermissionServiceClient.ServiceName = "PermissionServiceClient"

export type PermissionServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,

		_provider: PermissionProviderClient.PermissionProviderClient,
	},
	{} :: typeof({ __index = PermissionServiceClient })
))

--[=[
	Initializes the service. Should be done via [ServiceBag].

	@within PermissionServiceClient
	@param serviceBag ServiceBag
]=]
function PermissionServiceClient.Init(self: PermissionServiceClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	-- Constructed in Init so the packet listener is live before the server's
	-- push can arrive
	self._provider = self._maid:Add(PermissionProviderClient.new())
end

--[=[
	Returns whether the local player is an admin.

	@within PermissionServiceClient
	@param player Player | nil
	@return Promise<boolean>
]=]
function PermissionServiceClient.PromiseIsAdmin(
	self: PermissionServiceClient,
	player: Player?
): Promise.Promise<boolean>
	return self._provider:PromiseIsAdmin(player)
end

--[=[
	Asks the server whether a user id belongs to an admin.

	:::info
	Only reports on users in the game -- anyone else reads as false.
	:::

	@within PermissionServiceClient
	@param userId number
	@return Promise<boolean>
]=]
function PermissionServiceClient.PromiseIsUserAdmin(
	self: PermissionServiceClient,
	userId: number
): Promise.Promise<boolean>
	return self._provider:PromiseIsUserAdmin(userId)
end

--[=[
	Observes whether the local player is an admin.

	@within PermissionServiceClient
	@param player Player | nil
	@return Observable<boolean>
]=]
function PermissionServiceClient.ObserveIsAdmin(
	self: PermissionServiceClient,
	player: Player?
): Observable.Observable<boolean>
	return self._provider:ObserveIsAdmin(player)
end

--[=[
	Returns the permission provider.

	@within PermissionServiceClient
	@return Promise<PermissionProviderClient>
]=]
function PermissionServiceClient.PromisePermissionProvider(self: PermissionServiceClient): Promise.Promise<
	PermissionProviderClient.PermissionProviderClient
>
	return Promise.resolved(self._provider)
end

function PermissionServiceClient.Destroy(self: PermissionServiceClient)
	self._maid:Destroy()
end

return PermissionServiceClient
