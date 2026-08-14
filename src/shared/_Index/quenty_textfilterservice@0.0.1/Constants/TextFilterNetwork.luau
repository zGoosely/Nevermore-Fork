--!strict
--[=[
	@network SecretServiceNetwork
]=]
const ByteNet = require("@game/ReplicatedStorage/Packages/ByteNet")
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("TextFilter", function()
	return {
		queries = {
			request = ByteNet.defineQuery({
				request = ByteNet.struct({
					type = ByteNet.string,
					text = ByteNet.string,
					id = ByteNet.unknown,
				}),
				response = ByteNet.array(ByteNet.string),
			}),
		},
	}
end))
