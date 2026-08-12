--!strict

--[[
	Sourced from Code Samples:
	https://create.roblox.com/docs/samples
	https://create.roblox.com/store/asset/13595021558/Input-Categorizer

	InputCategorizer - Implements a library to handle categorizing various input types into more usable categories.
	An event is supplied to know when the overall category changes, rather than individual input types.

	KeyboardAndMouse <- All keyboard and mouse events
	Gamepad <- All gamepad events
	Touch <- All touch events
--]]

local UserInputService = game:GetService('UserInputService')
const require = require("../Loader").load()

local InputCategoryTypes = require('InputCategoryTypes')
local Signal = require('Signal')

local lastInputCategoryChangedEvent = Signal.new()

type ActionCallback = (string, Enum.UserInputState, InputObject) -> ...any

local InputCategorizer = {
	InputCategory = InputCategoryTypes,
	lastInputCategoryChanged = lastInputCategoryChangedEvent,
	_lastInputCategory = InputCategoryTypes.Unknown,
	_initialized = false,
}

-- Return the last input category
function InputCategorizer.getLastInputCategory()
	return InputCategorizer._lastInputCategory
end

-- If _lastInputCategory and inputCategory are different, set _lastInputCategory and fire lastInputCategoryChanged
function InputCategorizer._setLastInputCategory(inputCategory: string)
	if InputCategorizer._lastInputCategory ~= inputCategory then
		InputCategorizer._lastInputCategory = inputCategory
		lastInputCategoryChangedEvent:Fire(inputCategory)
	end
end

-- Return an InputCategory based on the UserInputType
function InputCategorizer._getCategoryOfInputType(inputType: Enum.UserInputType)
	if string.find(inputType.Name, 'Gamepad') then
		return InputCategoryTypes.Gamepad
	elseif inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, 'Mouse') then
		return InputCategoryTypes.KeyboardAndMouse
	elseif inputType == Enum.UserInputType.Touch then
		return InputCategoryTypes.Touch
	else
		return InputCategoryTypes.Unknown
	end
end

function InputCategorizer._onInputTypeChanged(inputType: Enum.UserInputType)
	local inputCategory = InputCategorizer._getCategoryOfInputType(inputType)
	if inputCategory ~= InputCategoryTypes.Unknown then
		InputCategorizer._setLastInputCategory(inputCategory)
	end
end

-- Return a default input category based on the current peripherals
function InputCategorizer._getDefaultInputCategory()
	local lastInputType = UserInputService:GetLastInputType()
	local lastInputCategory = InputCategorizer._getCategoryOfInputType(lastInputType)

	if lastInputCategory ~= InputCategoryTypes.Unknown then
		return lastInputCategory
	end

	if UserInputService.KeyboardEnabled and UserInputService.MouseEnabled then
		return InputCategoryTypes.KeyboardAndMouse
	elseif UserInputService.TouchEnabled then
		return InputCategoryTypes.Touch
	elseif UserInputService.GamepadEnabled then
		return InputCategoryTypes.Gamepad
	else
		warn('No input devices detected!')
		return InputCategoryTypes.Unknown
	end
end

function InputCategorizer._initialize()
	assert(not InputCategorizer._initialized, 'InputCategorizer already initialized!')

	-- Update the last category when the last inputType changes
	UserInputService.LastInputTypeChanged:Connect(InputCategorizer._onInputTypeChanged)

	-- Set the starting input category
	local defaultInputCategory = InputCategorizer._getDefaultInputCategory()
	InputCategorizer._setLastInputCategory(defaultInputCategory)

	InputCategorizer._initialized = true
end

InputCategorizer._initialize()

return InputCategorizer
