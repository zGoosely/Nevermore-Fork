--!strict
--[=[
	Replicates a player's admin status from [PermissionService] to
	[PermissionServiceClient].

	The server resolves permissions as each player joins and pushes that player
	their own status over `permissionsLoaded`. The server never listens for it,
	so a client firing it does nothing.

	To ask about somebody else, the client invokes the `isAdmin` query. It is
	answered from the server's already-resolved permissions, so it can only
	report on players in the game.

	@network PermissionServiceNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("Permissions", function()
	return {
		packets = {
			permissionsLoaded = ByteNet.definePacket({
				value = ByteNet.struct({
					isAdmin = ByteNet.bool,
				}),
			}),
		},

		queries = {
			-- userId is float64 because Roblox user ids have outgrown uint32
			isAdmin = ByteNet.defineQuery({
				request = ByteNet.struct({
					userId = ByteNet.float64,
				}),
				response = ByteNet.struct({
					isAdmin = ByteNet.bool,
				}),
			}),
		},
	}
end))
