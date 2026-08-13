--!strict
--[=[
	@class RoundingBehaviourTypes
]=]
local Enums = require("@game/ReplicatedStorage/Packages/Enums")

export type RoundingBehaviourType = "roundToClosest" | "truncate" | "None"

return Enums.new({
	ROUND_TO_CLOSEST = "roundToClosest" :: "roundToClosest",
	TRUNCATE = "truncate" :: "truncate",
	NONE = "none" :: "none",
})
