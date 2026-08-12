--!strict
--[=[
	@class FakeSkyboxRenderMethod
]=]

const require = require("../../Loader").load()

local SimpleEnum = require("Enums")

export type FakeSkyboxRenderMethod = "surfacegui" | "decal"

return SimpleEnum.new({
	SURFACEGUI = "surfacegui" :: "surfacegui",
	DECAL = "decal" :: "decal",
})
