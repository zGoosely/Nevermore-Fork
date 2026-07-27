--!strict
--[=[
	@network SecretServiceNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

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
