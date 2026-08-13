--!strict
--[=[
	@class SecretServiceClient
]=]
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const SecretServiceNetwork = require("./Constants/SecretServiceNetwork")

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
function SecretServiceClient.PromiseSecretKeyNamesList(_self: SecretServiceClient): Promise.Promise<{ string }>
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
