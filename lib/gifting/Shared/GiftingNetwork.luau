--!strict
--[=[
	Compact replication for the local player's gifts. Pending purchase intents and
	processed receipt IDs remain server-only.

	@network GiftingNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("Gifting", function()
	return {
		packets = {
			giftsChanged = ByteNet.definePacket({
				value = ByteNet.buff,
			}),
		},
		queries = {
			getGifts = ByteNet.defineQuery({
				request = ByteNet.nothing,
				response = ByteNet.buff,
			}),
		},
	}
end))
