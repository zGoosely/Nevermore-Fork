--!strict
--[=[
	Canonical InputCategoryTypes
	@class InputCategoryTypes
]=]

const require = require("../Loader").load()

local Enums = require('Enums')

export type InputCategoryType = 'KeyboardAndMouse' | 'Gamepad' | 'Touch' | 'Unknown'

return Enums.new({
	KeyboardAndMouse = 'KeyboardAndMouse' :: 'KeyboardAndMouse',
	Gamepad = 'Gamepad' :: 'Gamepad',
	Touch = 'Touch' :: 'Touch',
	Unknown = 'Unknown' :: 'Unknown',
})
