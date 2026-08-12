--!strict
--[=[
	Built-in planar movement controllers for simulated characters.

	@class SimulatedCharacterMovementController
]=]

const require = require("../../../Loader").load()

const Enums = require("Enums")

export type MovementController = number

return Enums.new({
	MANUAL = 0 :: number,
	CHASE = 1 :: number,
	WANDER = 2 :: number,
	GUARD = 3 :: number,
	ORBIT = 4 :: number,
})
