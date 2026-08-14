--!strict
--[=[
	Typed transport for lazy server-directory subscriptions, snapshots, and joins.

	@network ServerListNetwork
]=]
const ByteNet = require("@game/ReplicatedStorage/Packages/ByteNet")
const ServerListConstants = require("./ServerListConstants")
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace(ServerListConstants.NETWORK_NAMESPACE, function()
	const metadata = ByteNet.struct({
		jobId = ByteNet.string,
		placeId = ByteNet.float64,
		name = ByteNet.string,
		region = ByteNet.optional(ByteNet.string),
		regionSource = ByteNet.string,
		playerCount = ByteNet.uint16,
		maxPlayers = ByteNet.uint16,
		serverType = ByteNet.string,
		placeVersion = ByteNet.uint32,
		startedAt = ByteNet.float64,
		updatedAt = ByteNet.float64,
	})

	return {
		packets = {
			subscriptionChanged = ByteNet.definePacket({
				value = ByteNet.bool,
			}),
			snapshotRequested = ByteNet.definePacket({
				value = ByteNet.nothing,
			}),
			joinRequested = ByteNet.definePacket({
				value = ByteNet.string,
			}),
			snapshot = ByteNet.definePacket({
				value = ByteNet.array(metadata),
			}),
		},
	}
end))
