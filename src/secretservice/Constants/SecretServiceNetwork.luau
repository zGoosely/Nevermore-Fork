--!strict
--[=[
	@network SecretServiceNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("Secrets", function()
	return {
		queries = {
			requestSecretKeyNames = ByteNet.defineQuery({
				request = ByteNet.string,
				response = ByteNet.array(ByteNet.string),
			}),
		},
	}
end))
