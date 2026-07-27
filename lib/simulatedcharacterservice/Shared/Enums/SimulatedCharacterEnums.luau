--!strict
--[=[
	All enum lists used by SimulatedCharacterService registration.

	@class SimulatedCharacterEnums
]=]

const require = require("../../../Loader").load()

const SimulatedCharacterFacingMode = require("SimulatedCharacterFacingMode")
const SimulatedCharacterMovementController = require("SimulatedCharacterMovementController")
const SimulatedCharacterPlacementMode = require("SimulatedCharacterPlacementMode")
const SimulatedCharacterTargetingMode = require("SimulatedCharacterTargetingMode")
const SimulatedCharacterVariantSelectionMode = require("SimulatedCharacterVariantSelectionMode")

return table.freeze({
	FacingMode = SimulatedCharacterFacingMode,
	MovementController = SimulatedCharacterMovementController,
	PlacementMode = SimulatedCharacterPlacementMode,
	TargetingMode = SimulatedCharacterTargetingMode,
	VariantSelectionMode = SimulatedCharacterVariantSelectionMode,
})
