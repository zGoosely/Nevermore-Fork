--!strict
--[=[
	Tracks when a static [InputModeType] is used.

	@class InputMode
]=]

const require = require("../../Loader").load()

const DuckTypeUtils = require("DuckTypeUtils")
const InputModeType = require("InputModeType")
const Signal = require("Signal")
const t = require("t")

const InputMode = {}
InputMode.ClassName = "InputMode"
InputMode.__index = InputMode

export type InputMode = typeof(setmetatable(
	{} :: {
		_inputModeType: InputModeType.InputModeType,
		_lastEnabled: number,
		Name: string,
		Enabled: Signal.Signal<()>,
	},
	{} :: typeof({ __index = InputMode })
))

--[=[
	Creates runtime state for an input mode definition.

	@within InputMode
	@param inputModeType InputModeType
	@return InputMode
]=]
function InputMode.new(inputModeType: InputModeType.InputModeType): InputMode
	assert(InputModeType.isInputModeType(inputModeType), "Bad inputModeType")

	const self: InputMode = setmetatable({} :: any, InputMode)
	self._inputModeType = inputModeType
	self._lastEnabled = 0
	self.Name = inputModeType.Name
	self.Enabled = Signal.new()
	return self
end

--[=[
	Returns whether a value implements InputMode.

	@within InputMode
	@param value any
	@return boolean
]=]
function InputMode.isInputMode(value: any): boolean
	return DuckTypeUtils.isImplementation(InputMode, value)
end

--[=[
	Returns the last `os.clock()` time at which the mode was enabled.

	@within InputMode
	@return number
]=]
function InputMode.GetLastEnabledTime(self: InputMode): number
	return self._lastEnabled
end

--[=[
	Returns a copy of all keys defining the mode.

	@within InputMode
	@return { InputModeKey }
]=]
function InputMode.GetKeys(self: InputMode): { InputModeType.InputModeKey }
	return self._inputModeType:GetKeys()
end

--[=[
	Returns whether an input key belongs to the mode.

	@within InputMode
	@param inputType InputModeKey
	@return boolean
]=]
function InputMode.IsValid(self: InputMode, inputType: InputModeType.InputModeKey): boolean
	return self._inputModeType:IsValid(inputType)
end

--[=[
	Marks the mode as the most recently used mode and fires `Enabled`.

	@within InputMode
]=]
function InputMode.Enable(self: InputMode)
	self._lastEnabled = os.clock()
	self.Enabled:Fire()
end

--[=[
	Enables the mode when an InputObject's UserInputType or KeyCode matches it.

	@within InputMode
	@param inputObject InputObject
]=]
function InputMode.Evaluate(self: InputMode, inputObject: InputObject)
	assert(t.instanceIsA("InputObject")(inputObject), "Bad inputObject")
	if self._inputModeType:IsValid(inputObject.UserInputType) or self._inputModeType:IsValid(inputObject.KeyCode) then
		self:Enable()
	end
end

function InputMode.Destroy(self: InputMode)
	self.Enabled:Destroy()
	table.clear(self)
	setmetatable(self, nil)
end

return InputMode
