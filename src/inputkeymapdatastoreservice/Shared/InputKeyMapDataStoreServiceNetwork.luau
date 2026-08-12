--!strict
--[=[
	Carries untrusted input-binding changes from the local player to the server.
	Authoritative bindings replicate back through [PlayerDataStoreService].

	@network InputKeyMapDataStoreServiceNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("InputKeyMapDataStoreService", function()
	const serializedInputType = ByteNet.struct({
		Kind = ByteNet.uint8,
		Name = ByteNet.string,
		Modifiers = ByteNet.optional(ByteNet.array(ByteNet.string)),
	})

	return {
		packets = {
			bindingRequested = ByteNet.definePacket({
				value = ByteNet.struct({
					ProviderName = ByteNet.string,
					ListName = ByteNet.string,
					InputModeName = ByteNet.string,
					InputTypes = ByteNet.array(serializedInputType),
					Clear = ByteNet.bool,
				}),
			}),
		},
	}
end))
