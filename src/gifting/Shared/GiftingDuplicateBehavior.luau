--!strict
--[=[
	Controls how GiftAsync handles an existing gift with the same key.

	@class GiftingDuplicateBehavior
]=]

const require = require("../../Loader").load()

const Enums = require("Enums")

export type GiftingDuplicateBehavior = "keep" | "replace" | "stack"

return Enums.new({
	Keep = "keep" :: "keep",
	Replace = "replace" :: "replace",
	Stack = "stack" :: "stack",
	KEEP = "keep" :: "keep",
	REPLACE = "replace" :: "replace",
	STACK = "stack" :: "stack",
})
