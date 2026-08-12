--!strict
--[=[
	Utility functions for input type classification and comparison.

	@util InputTypeUtils
]=]

const require = require("../../../Loader").load()

const HttpService = game:GetService("HttpService")

const Set = require("Set")
const SlottedTouchButtonUtils = require("SlottedTouchButtonUtils")
const t = require("t")

--[=[
	A valid input type that can be represented here.

	@within InputTypeUtils
]=]
export type InputType =
	Enum.UserInputType
	| Enum.KeyCode
	| string
	| SlottedTouchButtonUtils.SlottedTouchButtonData
	| "TouchButton"
	| "Tap"
	| "Drag"
	| any

const InputTypeUtils = {}

--[=[
	Returns true if the input type is a known input type.

	@within InputTypeUtils
	@param inputType any
	@return boolean
]=]
function InputTypeUtils.isKnownInputType(inputType: any): boolean
	return InputTypeUtils.isTapInWorld(inputType)
		or InputTypeUtils.isRobloxTouchButton(inputType)
		or InputTypeUtils.isDrag(inputType)
		or SlottedTouchButtonUtils.isSlottedTouchButton(inputType)
		or (
			typeof(inputType) == "EnumItem"
			and (tostring(inputType.EnumType) == "UserInputType" or tostring(inputType.EnumType) == "KeyCode")
		)
end

--[=[
	Returns true if the input type is specifying a tap in the world.

	@within InputTypeUtils
	@param inputKey InputType
	@return boolean
]=]
function InputTypeUtils.isTapInWorld(inputKey: InputType): boolean
	return inputKey == "Tap"
end

--[=[
	Returns true if the input type is specifying a drag.

	@within InputTypeUtils
	@param inputKey InputType
	@return boolean
]=]
function InputTypeUtils.isDrag(inputKey: InputType): boolean
	return inputKey == "Drag"
end

--[=[
	Returns true if the input type is specifying a Roblox touch button.

	@within InputTypeUtils
	@param inputKey InputType
	@return boolean
]=]
function InputTypeUtils.isRobloxTouchButton(inputKey: InputType): boolean
	return inputKey == "TouchButton"
end

--[=[
	Specifies a tap in the world.

	@within InputTypeUtils
	@return "Tap"
]=]
function InputTypeUtils.createTapInWorld(): "Tap"
	return "Tap"
end

--[=[
	Specifies a roblox touch button.

	@within InputTypeUtils
	@return "TouchButton"
]=]
function InputTypeUtils.createRobloxTouchButton(): "TouchButton"
	return "TouchButton"
end

--[=[
	Computes a unique key for an inputType which can be used in a set.

	@within InputTypeUtils
	@param inputType InputType
	@return any
]=]
function InputTypeUtils.getUniqueKeyForInputType(inputType: InputType): any
	if SlottedTouchButtonUtils.isSlottedTouchButton(inputType) then
		return (inputType :: any).slotId
	else
		return inputType
	end
end

local function convertValuesToJSONIfNeeded(list: { any }): { [any]: any }
	const result = {}
	for key, value in list do
		if type(value) == "table" then
			result[key] = HttpService:JSONEncode(value)
		else
			result[key] = value
		end
	end
	return result
end

--[=[
	Expensive comparison check to see if InputTypes are the same or not.

	@within InputTypeUtils
	@param a { InputType }
	@param b { InputType }
	@return boolean
]=]
function InputTypeUtils.areInputTypesListsEquivalent(a: { InputType }, b: { InputType }): boolean
	assert(t.table(a), "Bad a")
	assert(t.table(b), "Bad b")

	const setA = Set.fromTableValue(convertValuesToJSONIfNeeded(a))
	const setB = Set.fromTableValue(convertValuesToJSONIfNeeded(b))

	const remaining = Set.difference(setA, setB)
	const left = Set.toList(remaining)
	return #left == 0
end

return InputTypeUtils
