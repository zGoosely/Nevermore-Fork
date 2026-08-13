--!strict
--[=[
	Results returned by GameProductService purchase handlers.

	@class GameProductHandlerResult
]=]
const Enums = require("@game/ReplicatedStorage/Packages/Enums")

export type GameProductHandlerResult = "grant" | "retry" | "skip"

return Enums.new({
	GRANT = "grant" :: "grant",
	RETRY = "retry" :: "retry",
	SKIP = "skip" :: "skip",
})
