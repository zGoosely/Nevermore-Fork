--!strict
--[=[
	Placement anchors supported by SimulatedCharacterService.

	@class SimulatedCharacterPlacementMode
]=]

const require = require("../../../Loader").load()

const Enums = require("Enums")

export type PlacementMode = number

return Enums.new({
	PIVOT = 0 :: number,
	BOUNDING_BOX_CENTER = 1 :: number,
	GROUNDED = 2 :: number,
})
