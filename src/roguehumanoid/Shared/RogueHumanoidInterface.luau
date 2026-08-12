--!strict
--[=[
	@class RogueHumanoidInterface
]=]

const require = require("../../Loader").load()

const TieDefinition = require("TieDefinition")

return TieDefinition.new("RogueHumanoid", {
	CreateMultiplier = TieDefinition.Types.METHOD,
	CreateAdditive = TieDefinition.Types.METHOD,
})
