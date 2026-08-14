--!strict
--[=[
	@class RogueHumanoidInterface
]=]
const TieDefinition = require("@game/ReplicatedStorage/Packages/TieDefinition")

return TieDefinition.new("RogueHumanoid", {
	CreateMultiplier = TieDefinition.Types.METHOD,
	CreateAdditive = TieDefinition.Types.METHOD,
})
