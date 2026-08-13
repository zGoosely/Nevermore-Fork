--!strict
--[=[
	ByteNet protocol for Cmdr command execution and server-to-client events.

	@network CmdrServiceNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

const MAX_COMMAND_LENGTH = 60_000

const network = ByteNet.defineNamespace("Cmdr", function()
	return {
		packets = {
			event = ByteNet.definePacket({
				value = ByteNet.struct({
					name = ByteNet.string,
					arguments = ByteNet.array(ByteNet.unknown),
				}),
			}),
		},
		queries = {
			execute = ByteNet.defineQuery({
				request = ByteNet.struct({
					text = ByteNet.string,
					data = ByteNet.optional(ByteNet.unknown),
				}),
				response = ByteNet.string,
			}),
		},
	}
end)

return TableUtils.deepReadonly({
	MAX_COMMAND_LENGTH = MAX_COMMAND_LENGTH,
	packets = network.packets,
	queries = network.queries,
})
