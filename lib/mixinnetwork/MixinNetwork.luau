--!strict
--[=[
	Mixes one operation from each ByteNet endpoint into a class or service table.

	@class MixinNetwork
]=]

const require = require("../Loader").load()

const StringUtils = require("StringUtils")
const t = require("t")

type NetworkMethod = (...any) -> ...any
type NetworkEndpoint = { [string]: any }

const MixinNetwork = {}

export type MixinNetwork = typeof(setmetatable({} :: {}, {} :: typeof({ __index = MixinNetwork })))

--[=[
	Adds a selected ByteNet operation from every endpoint to a class or service.
	Endpoint names are converted from lower camel case to PascalCase. The injected
	method discards its object `self` and forwards every other argument and return
	value to the selected ByteNet operation.

	For example, `MixinNetwork:Add(Service, Network.packets, "sendTo")` adds
	`Service:PurchaseProcessed(data, player)` for a `purchaseProcessed` packet.

	@within MixinNetwork
	@param class table -- Class or service module table that receives the methods.
	@param endpoints table -- A ByteNet `packets` or `queries` table.
	@param operationName string -- ByteNet operation to forward, such as `send`, `sendTo`, or `invoke`.
]=]
function MixinNetwork.Add(
	_self: MixinNetwork,
	class: { [any]: any },
	endpoints: { [string]: NetworkEndpoint },
	operationName: string
): ()
	assert(t.table(class), "Bad class")
	assert(t.table(endpoints), "Bad endpoints")
	assert(t.string(operationName) and operationName ~= "", "Bad operationName")

	for endpointName, endpoint in endpoints do
		assert(t.string(endpointName) and endpointName ~= "", "Bad endpointName")
		assert(t.table(endpoint), `Bad endpoint {endpointName}`)

		const networkMethod = endpoint[operationName]
		assert(t.callback(networkMethod), `Bad endpoints.{endpointName}.{operationName}`)

		const methodName = StringUtils.uppercaseFirstLetter(endpointName)
		assert(class[methodName] == nil, `{methodName} is already defined on class`)

		class[methodName] = function(_objectSelf: any, ...: any): ...any
			return (networkMethod :: NetworkMethod)(...)
		end
	end
end

return MixinNetwork
