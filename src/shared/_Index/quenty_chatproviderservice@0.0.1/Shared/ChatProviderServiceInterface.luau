--!strict
--[=[
	Tie contract for observing user chat tags.

	@class ChatProviderServiceInterface
]=]

local TieDefinition = require("@game/ReplicatedStorage/Packages/TieDefinition")

return TieDefinition.new("ChatProviderService", {
	ObserveUserTagsByName = TieDefinition.Types.METHOD,
	ObserveUserTagsByNameBrio = TieDefinition.Types.METHOD,
})
