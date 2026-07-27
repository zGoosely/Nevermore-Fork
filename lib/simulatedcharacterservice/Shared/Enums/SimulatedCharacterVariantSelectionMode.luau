--!strict
--[=[
	Template variant selection policies.

	@class SimulatedCharacterVariantSelectionMode
]=]

const require = require("../../../Loader").load()

const Enums = require("Enums")

export type VariantSelectionMode = number

return Enums.new({
	WEIGHTED = 0 :: number,
	RANDOM = 1 :: number,
	SEQUENTIAL = 2 :: number,
})
