--!strict
--[=[
	Compact server-to-client purchase results for GameProductService.

	@network GameProductNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("GameProducts", function()
	return {
		packets = {
			purchaseProcessed = ByteNet.definePacket({
				value = ByteNet.struct({
					assetType = ByteNet.uint8,
					assetId = ByteNet.uint32,
					purchased = ByteNet.bool,
				}),
			}),
		},
	}
end))
