--!strict
--[=[
	Handles on-demand template requests from [TemplateProvider] clients.

	Clients can only request opaque template ids advertised by a provider's
	tombstones. The server validates the provider and template before temporarily
	replicating a clone to that player's PlayerGui.

	@network TemplateProviderNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("TemplateProvider", function()
	return {
		queries = {
			requestTemplate = ByteNet.defineQuery({
				request = ByteNet.struct({
					providerName = ByteNet.string,
					templateId = ByteNet.string,
				}),
				response = ByteNet.struct({
					success = ByteNet.bool,
					transferId = ByteNet.optional(ByteNet.string),
					errorMessage = ByteNet.optional(ByteNet.string),
				}),
			}),
		},
	}
end))
