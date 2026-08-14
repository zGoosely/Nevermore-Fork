--!strict
--[=[
	Defines tags, attributes, defaults, and scheduler budgets for client culling.

	@util ClientCullingConstants
]=]
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly({
	CULL_TAG = "Cull",
	CULL_SHADOWS_TAG = "CullShadows",

	CULL_DISTANCE_ATTRIBUTE = "CullDistance",
	CULL_UNCULL_DISTANCE_ATTRIBUTE = "CullUncullDistance",
	CULL_DYNAMIC_ATTRIBUTE = "CullDynamic",

	DEFAULT_CULL_DISTANCE = 200,
	DEFAULT_UPDATE_FREQUENCY = 10,
	DEFAULT_UNCULL_HYSTERESIS = 10,
	MINIMUM_SPATIAL_CELL_SIZE = 32,

	MAX_DYNAMIC_REFRESHES_PER_UPDATE = 256,
	MAX_VISUAL_MUTATIONS_PER_FRAME = 512,
})
