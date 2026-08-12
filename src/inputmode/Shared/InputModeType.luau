--!strict
--[=[
	Defines a static group of input keys used by [InputMode]. Definitions can
	include other InputModeTypes to form composite modes.

	@class InputModeType
]=]

const require = require("../../Loader").load()

const DuckTypeUtils = require("DuckTypeUtils")
const t = require("t")

const InputModeType = {}
InputModeType.ClassName = "InputModeType"
InputModeType.__index = InputModeType

export type InputModeKey = Enum.UserInputType | Enum.KeyCode | string

export type InputModeType = typeof(setmetatable(
	{} :: {
		_keys: { InputModeKey },
		_valid: { [InputModeKey]: boolean },
		Name: string,
	},
	{} :: typeof({ __index = InputModeType })
))

export type InputModeTypeDefinition = { InputModeType | InputModeKey }

--[=[
	Creates an input mode definition.

	@within InputModeType
	@param name string
	@param typesAndInputModeTypes InputModeTypeDefinition
	@return InputModeType
]=]
function InputModeType.new(name: string, typesAndInputModeTypes: InputModeTypeDefinition): InputModeType
	assert(t.string(name) and name ~= "", "Bad name")
	assert(t.table(typesAndInputModeTypes), "Bad typesAndInputModeTypes")

	const self: InputModeType = setmetatable({} :: any, InputModeType)
	self._valid = {}
	self._keys = {}
	self.Name = name
	self:_addValidTypesFromTable(typesAndInputModeTypes)
	return self
end

--[=[
	Returns whether a value implements InputModeType.

	@within InputModeType
	@param value any
	@return boolean
]=]
function InputModeType.isInputModeType(value: any): boolean
	return DuckTypeUtils.isImplementation(InputModeType, value)
end

--[=[
	Returns whether an input key belongs to this mode.

	@within InputModeType
	@param inputType InputModeKey
	@return boolean
]=]
function InputModeType.IsValid(self: InputModeType, inputType: InputModeKey): boolean
	assert(inputType ~= nil, "Bad inputType")
	return self._valid[inputType] == true
end

--[=[
	Returns a copy of every key defining this mode.

	@within InputModeType
	@return { InputModeKey }
]=]
function InputModeType.GetKeys(self: InputModeType): { InputModeKey }
	return table.clone(self._keys)
end

function InputModeType._addValidTypesFromTable(self: InputModeType, keys: InputModeTypeDefinition)
	for _, key in keys do
		if typeof(key) == "EnumItem" or type(key) == "string" then
			const inputKey = key :: InputModeKey
			if not self._valid[inputKey] then
				self._valid[inputKey] = true
				table.insert(self._keys, inputKey)
			end
		elseif InputModeType.isInputModeType(key) then
			self:_addInputModeType(key :: InputModeType)
		else
			warn(`[InputModeType] - Ignoring invalid key {tostring(key)} ({typeof(key)})`)
		end
	end
end

function InputModeType._addInputModeType(self: InputModeType, inputModeType: InputModeType)
	assert(InputModeType.isInputModeType(inputModeType), "Bad inputModeType")
	for _, key in inputModeType._keys do
		if not self._valid[key] then
			self._valid[key] = true
			table.insert(self._keys, key)
		end
	end
end

return InputModeType
