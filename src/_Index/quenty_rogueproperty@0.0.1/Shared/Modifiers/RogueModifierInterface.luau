--!strict
--[=[
	@class RogueModifierInterface
]=]
local TieDefinition = require("@game/ReplicatedStorage/Packages/TieDefinition")

return TieDefinition.new("RogueModifier", {
	Order = TieDefinition.Types.PROPERTY,
	Source = TieDefinition.Types.PROPERTY,

	--
	GetModifiedVersion = TieDefinition.Types.METHOD,
	ObserveModifiedVersion = TieDefinition.Types.METHOD,
	GetInvertedVersion = TieDefinition.Types.METHOD,
})
