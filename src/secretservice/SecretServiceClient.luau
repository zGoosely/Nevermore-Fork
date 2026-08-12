--!strict
--[=[
	@class SecretServiceClient
]=]

const require = require("../Loader").load()

const Maid = require("Maid")
const Promise = require("Promise")
const ServiceBag = require("ServiceBag")
const SecretServiceNetwork = require("SecretServiceNetwork")

const SecretServiceClient = {}
SecretServiceClient.ServiceName = "SecretServiceClient"

export type SecretServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
	},
	{} :: typeof({ __index = SecretServiceClient })
))

function SecretServiceClient.Init(self: SecretServiceClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
end

--[=[
	Promises all secret names

	@within SecretServiceClient
	@return Promise.Promise<{string}>
]=]
function SecretServiceClient.PromiseSecretKeyNamesList(self: SecretServiceClient): Promise.Promise<{ string }>
	const promise = Promise.new()
	const success, resultOrErr = pcall(function()
		return SecretServiceNetwork.queries.requestSecretKeyNames.invoke()
	end)

	if not success then
		warn(`[SecretServiceClient] - Failure while requesting KeyNames ({resultOrErr})`)
		promise:Reject()
	end

	promise:Resolve(resultOrErr)
	return promise
end

function SecretServiceClient.Destroy(self: SecretServiceClient)
	self._maid:Destroy()
end

return SecretServiceClient
