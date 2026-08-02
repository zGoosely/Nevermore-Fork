--!strict
--[=[
	Provides a lazy, immutable client mirror of the place server directory.

	@class ServerListServiceClient
	@client
]=]

const require = require("../Loader").load()

const Maid = require("Maid")
const Observable = require("Observable")
const Promise = require("Promise")
const Rx = require("Rx")
const ServerListConstants = require("ServerListConstants")
const ServerListFilters = require("ServerListFilters")
const ServerListNetwork = require("ServerListNetwork")
const ServerListTypes = require("ServerListTypes")
const ServerListUtils = require("ServerListUtils")
const ServiceBag = require("ServiceBag")
const Signal = require("Signal")
const t = require("t")

type FilterDescriptor = ServerListTypes.FilterDescriptor
type ServerMetadata = ServerListTypes.ServerMetadata

const ServerListServiceClient = {}
ServerListServiceClient.ServiceName = "ServerListServiceClient"

export type ServerListServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_cache: { ServerMetadata },
		_serversChanged: Signal.Signal<>,
		_observerCount: number,
	},
	{} :: typeof({ __index = ServerListServiceClient })
))

function ServerListServiceClient.Init(self: ServerListServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._cache = ServerListUtils.createSnapshot({})
	self._serversChanged = self._maid:Add(Signal.new())
	self._observerCount = 0

	const snapshot = ServerListNetwork.packets.snapshot
	const function handleSnapshot(servers: any)
		if not t.array(ServerListUtils.isServerMetadata)(servers) then
			warn("[ServerListServiceClient] - Ignoring malformed server snapshot")
			return
		end
		self._cache = ServerListUtils.createSnapshot(servers)
		self._serversChanged:Fire()
	end
	snapshot.listen(handleSnapshot)
	self._maid:Add(function()
		ServerListUtils.removeNetworkListener(snapshot, handleSnapshot)
	end)
end

--[=[
	Returns the latest shared server-directory snapshot. The array and every metadata
	record are frozen, so sharing it does not expose mutable service state.

	@within ServerListServiceClient
	@return { ServerMetadata }
]=]
function ServerListServiceClient.GetServers(self: ServerListServiceClient): { ServerMetadata }
	return self._cache
end

--[=[
	Returns the latest immutable snapshot after applying local filters. Predicate
	filters run before the single configured ordering filter.

	@within ServerListServiceClient
	@param filters { FilterDescriptor }
	@return { ServerMetadata }
]=]
function ServerListServiceClient.GetServersByFilters(
	self: ServerListServiceClient,
	filters: { FilterDescriptor }
): { ServerMetadata }
	return ServerListFilters.apply(self._cache, filters)
end

--[=[
	Observes immutable full snapshots. The first local observer enables the shared
	server refresh, and the last observer disables it.

	@within ServerListServiceClient
	@return Observable
]=]
function ServerListServiceClient.ObserveServers(
	self: ServerListServiceClient
): Observable.Observable<{ ServerMetadata }>
	return Observable.new(function(sub)
		const maid = Maid.new()
		self._observerCount += 1

		const function update()
			sub:Fire(self:GetServers())
		end
		maid:Add(self._serversChanged:Connect(update))
		update()

		if self._observerCount == 1 then
			ServerListNetwork.packets.subscriptionChanged.send(true)
			ServerListNetwork.packets.snapshotRequested.send()
		end

		maid:Add(function()
			self._observerCount -= 1
			if self._observerCount == 0 then
				ServerListNetwork.packets.subscriptionChanged.send(false)
			end
		end)
		return maid
	end) :: any
end

--[=[
	Observes immutable snapshots after applying local filters. The filter array is
	copied when this method is called, so later caller mutation has no effect.

	@within ServerListServiceClient
	@param filters { FilterDescriptor }
	@return Observable
]=]
function ServerListServiceClient.ObserveServersByFilters(
	self: ServerListServiceClient,
	filters: { FilterDescriptor }
): Observable.Observable<{ ServerMetadata }>
	const filterSnapshot = ServerListFilters.createSnapshot(filters)
	return self:ObserveServers():Pipe({
		Rx.map(function(servers: { ServerMetadata }): { ServerMetadata }
			return ServerListFilters.apply(servers, filterSnapshot)
		end),
	})
end

--[=[
	Sends a bounded join request to the server. The promise resolves once the request
	has been encoded and queued locally; teleport acceptance and completion remain
	server-authoritative and may occur afterward.

	@within ServerListServiceClient
	@param jobId string
	@return Promise
]=]
function ServerListServiceClient.JoinServerAsync(_self: ServerListServiceClient, jobId: string): Promise.Promise<()>
	assert(t.string(jobId) and jobId ~= "" and #jobId <= ServerListConstants.MAX_JOB_ID_LENGTH, "Bad jobId")

	ServerListNetwork.packets.joinRequested.send(jobId)
	return Promise.resolved()
end

function ServerListServiceClient.Destroy(self: ServerListServiceClient): ()
	if self._observerCount > 0 then
		ServerListNetwork.packets.subscriptionChanged.send(false)
	end
	self._maid:DoCleaning()
end

return ServerListServiceClient
