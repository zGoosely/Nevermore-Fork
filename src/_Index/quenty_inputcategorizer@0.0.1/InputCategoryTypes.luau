--!strict
--[=[
	Canonical InputCategoryTypes
	@class InputCategoryTypes
]=]
local Enums = require("@game/ReplicatedStorage/Packages/Enums")

export type InputCategoryType = "KeyboardAndMouse" | "Gamepad" | "Touch" | "Unknown"

return Enums.new({
	KeyboardAndMouse = "KeyboardAndMouse" :: "KeyboardAndMouse",
	Gamepad = "Gamepad" :: "Gamepad",
	Touch = "Touch" :: "Touch",
	Unknown = "Unknown" :: "Unknown",
})
