--!strict
--[=[
	Holds the admin status the server pushed over [PermissionServiceNetwork].
	See [PermissionServiceClient].

	Only the local player's permissions are ever replicated, so this provider
	answers for the local player alone.

	@client
	@class PermissionProviderClient
]=]

const Players = game:GetService("Players")

const require = require("../../../Loader").load()

const Maid = require("Maid")
const Promise = require("Promise")
const Observable = require("Observable")
const Rx = require("Rx")
const PermissionServiceNetwork = require("PermissionServiceNetwork")

const PermissionProviderClient = {}
PermissionProviderClient.ClassName = "PermissionProviderClient"
PermissionProviderClient.__index = PermissionProviderClient

export type PermissionProviderClient = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_isAdminPromise: Promise.Promise<boolean>,
	},
	{} :: typeof({ __index = PermissionProviderClient })
))

function PermissionProviderClient.new(): PermissionProviderClient
	const self: PermissionProviderClient = setmetatable({} :: any, PermissionProviderClient)

	self._maid = Maid.new()
	self._isAdminPromise = self._maid:GivePromise(Promise.new())
	PermissionServiceNetwork.packets.permissionsLoaded.listen(function(value: { isAdmin: boolean })
		self._isAdminPromise:Resolve(value.isAdmin)
	end)

	return self
end

--[=[
	Returns whether the local player is an admin, once the server has said so.

	@within PermissionProviderClient
	@param player Player | nil
	@return Promise<boolean>
]=]
function PermissionProviderClient.PromiseIsAdmin(
	self: PermissionProviderClient,
	player: Player?
): Promise.Promise<boolean>
	assert(player == nil or player == Players.LocalPlayer, "We only support the local player")

	return self._isAdminPromise
end

--[=[
	Asks the server whether a user id belongs to an admin.

	:::info
	Only reports on users in the game -- anyone else reads as false.
	:::

	@within PermissionProviderClient
	@param userId number
	@return Promise<boolean>
]=]
function PermissionProviderClient.PromiseIsUserAdmin(
	_self: PermissionProviderClient,
	userId: number
): Promise.Promise<boolean>
	assert(type(userId) == "number", "Bad userId")

	return Promise.spawn(function(resolve, reject)
		const success, response = pcall(PermissionServiceNetwork.queries.isAdmin.invoke, {
			userId = userId,
		})

		if not success then
			return reject(response)
		end

		resolve(type(response) == "table" and response.isAdmin == true)
	end)
end

--[=[
	Observes whether the local player is an admin.

	@within PermissionProviderClient
	@param player Player | nil
	@return Observable<boolean>
]=]
function PermissionProviderClient.ObserveIsAdmin(
	self: PermissionProviderClient,
	player: Player?
): Observable.Observable<boolean>
	return Rx.fromPromise(self:PromiseIsAdmin(player))
end

function PermissionProviderClient.Destroy(self: PermissionProviderClient)
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return PermissionProviderClient
