--!strict
--[=[
	Input-mode values exposed on Player attributes.

	@class PlayerInputModeTypes
]=]

const require = require("../../Loader").load()

const Enums = require("Enums")

export type PlayerInputModeType = "GAMEPAD" | "KEYBOARD" | "TOUCH"

return Enums.new({
	GAMEPAD = "GAMEPAD" :: "GAMEPAD",
	KEYBOARD = "KEYBOARD" :: "KEYBOARD",
	TOUCH = "TOUCH" :: "TOUCH",
})
