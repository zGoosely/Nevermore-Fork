--!strict
--[=[
	Client mirror for reading and observing server-assigned uint8 player IDs.

	@class PlayerIdServiceClient
	@client
]=]

const Players = game:GetService("Players")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const PlayerIdServiceInterface = require("./Shared/PlayerIdServiceInterface")
const PlayerIdServiceUtils = require("./Shared/PlayerIdServiceUtils")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const TieRealmService = require("@game/ReplicatedStorage/Packages/TieRealmService")

const PlayerIdServiceClient = {}
PlayerIdServiceClient.ServiceName = "PlayerIdServiceClient"

export type PlayerIdServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
	},
	{} :: typeof({ __index = PlayerIdServiceClient })
))

--[=[
	Initializes the client service and exposes its Tie interface.

	@param serviceBag Service bag used to resolve dependencies.
]=]
function PlayerIdServiceClient.Init(self: PlayerIdServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._serviceBag:GetService(TieRealmService)

	self._maid:Add((PlayerIdServiceInterface :: any).Client:Implement(Players, self))
end

--[=[
	Returns the replicated player ID assigned to `player`.

	The returned value is a compact uint8 identifier assigned by the server and is
	unique for the lifetime of the player's session. Returns `nil` until the ID
	has been replicated.

	@param player The player to query.
	@return The replicated player ID, or `nil` if unavailable.
]=]
function PlayerIdServiceClient.GetId(_self: PlayerIdServiceClient, player: Player): number?
	return PlayerIdServiceUtils.getId(player)
end

--[=[
	Observes the replicated player ID for `player`.

	The observable immediately emits the current value (which may be `nil`) and
	then emits again whenever the replicated ID changes.

	@param player The player to observe.
	@return Observable emitting the player's replicated ID.
]=]
function PlayerIdServiceClient.Observe(_self: PlayerIdServiceClient, player: Player): Observable.Observable<number?>
	return PlayerIdServiceUtils.observeId(player)
end

--[=[
	Alias for `:Observe()`.

	@param player The player to observe.
	@return Observable emitting the player's replicated ID.
]=]
PlayerIdServiceClient.ObserveId = PlayerIdServiceClient.Observe

--[=[
	Cleans up the service and disconnects all resources.
]=]
function PlayerIdServiceClient.Destroy(self: PlayerIdServiceClient): ()
	self._maid:Destroy()
end

return PlayerIdServiceClient
