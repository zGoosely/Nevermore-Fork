--!strict
--[=[
	@class RagdollableInterface
]=]
local TieDefinition = require("@game/ReplicatedStorage/Packages/TieDefinition")

return TieDefinition.new("Ragdollable", {
	Ragdolled = TieDefinition.Types.SIGNAL,
	Unragdolled = TieDefinition.Types.SIGNAL,

	Ragdoll = TieDefinition.Types.METHOD,
	Unragdoll = TieDefinition.Types.METHOD,
	ObserveIsRagdolled = TieDefinition.Types.METHOD,
	IsRagdolled = TieDefinition.Types.METHOD,
})
