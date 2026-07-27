--!strict
--[=[
	Target acquisition modes supported by simulated characters.

	@class SimulatedCharacterTargetingMode
]=]

const require = require("../../../Loader").load()

const Enums = require("Enums")

export type TargetingMode = number

return Enums.new({
	MANUAL = 0 :: number,
	NEAREST_PLAYER = 1 :: number,
})
