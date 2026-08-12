--!strict
--[=[
	Utilities for Roblox `NumberRange` values.

	@util NumberRangeUtils
]=]

local NumberRangeUtils = {}

--[=[
	Scales both ends of a NumberRange.

	@within NumberRangeUtils
	@param numberRange NumberRange
	@param scale number
	@return NumberRange
]=]
function NumberRangeUtils.scale(numberRange: NumberRange, scale: number): NumberRange
	assert(typeof(numberRange) == "NumberRange", "Bad numberRange")
	assert(type(scale) == "number", "Bad scale")

	return NumberRange.new(numberRange.Min * scale, numberRange.Max * scale)
end

--[=[
	Samples a NumberRange at an alpha between zero and one.

	@within NumberRangeUtils
	@param numberRange NumberRange
	@param alpha number
	@return number
]=]
function NumberRangeUtils.getValue(numberRange: NumberRange, alpha: number): number
	assert(typeof(numberRange) == "NumberRange", "Bad numberRange")
	assert(type(alpha) == "number", "Bad alpha")

	return numberRange.Min + (numberRange.Max - numberRange.Min) * alpha
end

return NumberRangeUtils
