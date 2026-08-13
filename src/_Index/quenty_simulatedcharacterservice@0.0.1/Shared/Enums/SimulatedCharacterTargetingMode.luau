--!strict
--[=[
	Target acquisition modes supported by simulated characters.

	@class SimulatedCharacterTargetingMode
]=]
const Enums = require("@game/ReplicatedStorage/Packages/Enums")

export type TargetingMode = number

return Enums.new({
	MANUAL = 0 :: number,
	NEAREST_PLAYER = 1 :: number,
})
