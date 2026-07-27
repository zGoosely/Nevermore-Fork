--!strict
--[=[
	@class GlobalLightSourceType
]=]

local require = require("../Loader").load()

local SimpleEnum = require("Enums")

export type GlobalLightSourceType = "sun" | "moon"

return SimpleEnum.new({
	SUN = "sun" :: "sun",
	MOON = "moon" :: "moon",
})
