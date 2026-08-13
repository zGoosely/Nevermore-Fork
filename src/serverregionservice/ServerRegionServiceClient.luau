--!strict
--[=[
	Reads the server region replicated through ReplicatedStorage.

	@class ServerRegionServiceClient
	@client
]=]

const require = require("../Loader").load()

const Maid = require("Maid")
const Promise = require("Promise")
const ServerRegionServiceUtils = require("ServerRegionServiceUtils")
const ServiceBag = require("ServiceBag")
const t = require("t")

const ServerRegionServiceClient = {}
ServerRegionServiceClient.ServiceName = "ServerRegionServiceClient"

export type ServerRegionServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
	},
	{} :: typeof({ __index = ServerRegionServiceClient })
))

function ServerRegionServiceClient.Init(self: ServerRegionServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
end

--[=[
	Returns the currently replicated server region, or nil while unavailable.

	@within ServerRegionServiceClient
	@return string?
]=]
function ServerRegionServiceClient.GetRegion(_self: ServerRegionServiceClient): string?
	return ServerRegionServiceUtils.getRegion()
end

--[=[
	Returns a promise that resolves once the server region attribute replicates.

	@within ServerRegionServiceClient
	@return Promise<string>
]=]
function ServerRegionServiceClient.PromiseRegion(_self: ServerRegionServiceClient): Promise.Promise<string>
	return ServerRegionServiceUtils.promiseRegion()
end

function ServerRegionServiceClient.Destroy(self: ServerRegionServiceClient): ()
	self._maid:DoCleaning()
end

return ServerRegionServiceClient
