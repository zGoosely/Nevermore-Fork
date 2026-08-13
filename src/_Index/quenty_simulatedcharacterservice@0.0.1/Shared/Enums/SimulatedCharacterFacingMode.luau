--!strict
--[=[
	Facing policies supported by simulated characters.

	@class SimulatedCharacterFacingMode
]=]
const Enums = require("@game/ReplicatedStorage/Packages/Enums")

export type FacingMode = number

return Enums.new({
	MOVEMENT = 0 :: number,
	TARGET_WHEN_STOPPED = 1 :: number,
	TARGET_ALWAYS = 2 :: number,
})
