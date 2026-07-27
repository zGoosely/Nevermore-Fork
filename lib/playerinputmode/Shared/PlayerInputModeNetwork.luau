--!strict
--[=[
	ByteNet protocol used to report the local player's selected input mode to the
	server. The payload is one uint8; the server validates the code before setting
	the replicated Player attribute.

	@network PlayerInputModeNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("PlayerInputMode", function()
	return {
		packets = {
			inputModeChanged = ByteNet.definePacket({
				value = ByteNet.uint8,
			}),
		},
	}
end))
