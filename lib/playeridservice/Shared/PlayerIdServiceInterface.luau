--!strict
--[=[
	Realm-aware Tie contract implemented on the Players service.

	Shared implementations expose ID reads and observation. Only the server realm
	can refresh or author assignments.

	@class PlayerIdServiceInterface
]=]

const require = require("../../Loader").load()

const TieDefinition = require("TieDefinition")

return TieDefinition.new("PlayerIdService", {
	GetId = TieDefinition.Types.METHOD,
	ObserveId = TieDefinition.Types.METHOD,

	[TieDefinition.Realms.SERVER] = {
		RefreshIds = TieDefinition.Types.METHOD,
		SetIds = TieDefinition.Types.METHOD,
	},
})
