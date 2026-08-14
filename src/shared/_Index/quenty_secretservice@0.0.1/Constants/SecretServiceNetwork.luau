--!strict
--[=[
	@network SecretServiceNetwork
]=]
const ByteNet = require("@game/ReplicatedStorage/Packages/ByteNet")
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

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
