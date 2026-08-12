--!strict
--[=[
	Replicates player data from [PlayerDataStoreService] to [PlayerDataStoreServiceClient].

	On join the server sends that player their whole profile as one buffer
	(`profileLoaded`, hidden keys blanked) and then streams `valueChanged` deltas.
	The server never listens to either, so a client firing them does nothing.

	`settingRequested` is the one thing a client may write, and it is a request
	rather than a write: the server validates the name and value against
	`ProfileData.Template.Settings` and only then applies it. A rejected request is
	answered with a `valueChanged` carrying the authoritative value, which is what
	rolls the client's optimistic guess back. See [PlayerDataStoreServiceClient.SetSetting].

	Values are `unknown` because this store is generic. Pin down a schema and swap
	in precise types if you want the bandwidth back -- that is the point of ByteNet.

	@network PlayerDataStoreServiceNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("PlayerDataStoreService", function()
	return {
		packets = {
			profileLoaded = ByteNet.definePacket({
				value = ByteNet.struct({
					data = ByteNet.buff,
					hiddenKeys = ByteNet.array(ByteNet.string),
				}),
			}),

			valueChanged = ByteNet.definePacket({
				value = ByteNet.struct({
					name = ByteNet.string,
					value = ByteNet.unknown,
				}),
			}),

			-- Client -> server. Untrusted: name and value are whatever the client
			-- felt like sending, so the server validates both before applying.
			settingRequested = ByteNet.definePacket({
				value = ByteNet.struct({
					name = ByteNet.string,
					value = ByteNet.unknown,
				}),
			}),
		},
	}
end))
