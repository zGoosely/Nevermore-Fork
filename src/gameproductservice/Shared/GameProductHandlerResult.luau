--!strict
--[=[
	Results returned by GameProductService purchase handlers.

	@class GameProductHandlerResult
]=]

const require = require("../../Loader").load()

const Enums = require("Enums")

export type GameProductHandlerResult = "grant" | "retry" | "skip"

return Enums.new({
	GRANT = "grant" :: "grant",
	RETRY = "retry" :: "retry",
	SKIP = "skip" :: "skip",
})
