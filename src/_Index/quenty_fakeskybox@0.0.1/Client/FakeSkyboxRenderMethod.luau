--!strict
--[=[
	@class FakeSkyboxRenderMethod
]=]
local SimpleEnum = require("@game/ReplicatedStorage/Packages/Enums")

export type FakeSkyboxRenderMethod = "surfacegui" | "decal"

return SimpleEnum.new({
	SURFACEGUI = "surfacegui" :: "surfacegui",
	DECAL = "decal" :: "decal",
})
