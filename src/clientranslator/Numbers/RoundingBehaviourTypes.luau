--!strict
--[=[
	@class RoundingBehaviourTypes
]=]

const require = require("../../Loader").load()

local Enums = require("Enums")

export type RoundingBehaviourType = "roundToClosest" | "truncate" | "None"

return Enums.new({
	ROUND_TO_CLOSEST = "roundToClosest" :: "roundToClosest",
	TRUNCATE = "truncate" :: "truncate",
	NONE = "none" :: "none",
})
