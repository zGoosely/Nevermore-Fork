--!strict
--[=[
	Evaluates InputObjects against a collection of [InputMode] states.

	@class InputModeProcessor
]=]

const require = require("../../Loader").load()

const InputMode = require("InputMode")
const t = require("t")

const InputModeProcessor = {}
InputModeProcessor.ClassName = "InputModeProcessor"
InputModeProcessor.__index = InputModeProcessor

export type InputModeProcessor = typeof(setmetatable(
	{} :: {
		_inputModes: { InputMode.InputMode },
	},
	{} :: typeof({ __index = InputModeProcessor })
))

--[=[
	Creates an input mode processor.

	@within InputModeProcessor
	@param inputModes { InputMode }?
	@return InputModeProcessor
]=]
function InputModeProcessor.new(inputModes: { InputMode.InputMode }?): InputModeProcessor
	const self: InputModeProcessor = setmetatable({} :: any, InputModeProcessor)
	self._inputModes = {}

	if inputModes then
		for _, inputMode in inputModes do
			self:AddInputMode(inputMode)
		end
	end

	return self
end

--[=[
	Adds an InputMode to evaluate.

	@within InputModeProcessor
	@param inputMode InputMode
]=]
function InputModeProcessor.AddInputMode(self: InputModeProcessor, inputMode: InputMode.InputMode)
	assert(InputMode.isInputMode(inputMode), "Bad inputMode")
	assert(table.find(self._inputModes, inputMode) == nil, "Input mode already added")
	table.insert(self._inputModes, inputMode)
end

--[=[
	Returns a copy of every registered InputMode.

	@within InputModeProcessor
	@return { InputMode }
]=]
function InputModeProcessor.GetStates(self: InputModeProcessor): { InputMode.InputMode }
	return table.clone(self._inputModes)
end

--[=[
	Evaluates an InputObject against every registered mode.

	@within InputModeProcessor
	@param inputObject InputObject
]=]
function InputModeProcessor.Evaluate(self: InputModeProcessor, inputObject: InputObject)
	assert(t.instanceIsA("InputObject")(inputObject), "Bad inputObject")
	for _, inputMode in self._inputModes do
		inputMode:Evaluate(inputObject)
	end
end

function InputModeProcessor.Destroy(self: InputModeProcessor)
	table.clear(self)
	setmetatable(self, nil)
end

return InputModeProcessor
