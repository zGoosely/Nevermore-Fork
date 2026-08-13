--!strict
--[=[
	@class GlobalLightSourceType
]=]
local SimpleEnum = require("@game/ReplicatedStorage/Packages/Enums")

export type GlobalLightSourceType = "sun" | "moon"

return SimpleEnum.new({
	SUN = "sun" :: "sun",
	MOON = "moon" :: "moon",
})
