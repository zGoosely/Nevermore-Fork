--!strict
--[=[
	Color-picker presentation utilities.

	@util ColorPickerUtils
]=]

const require = require("../../Loader").load()

const LuvColor3Utils = require("LuvColor3Utils")

const ColorPickerUtils = {}

--[=[
	Returns a perceptually contrasting outline color for the supplied background.

	@within ColorPickerUtils
	@param color Color3
	@param backingColor Color3
	@return Color3
]=]
function ColorPickerUtils.getOutlineWithContrast(color: Color3, backingColor: Color3): Color3
	assert(typeof(color) == "Color3", "Bad color")
	assert(typeof(backingColor) == "Color3", "Bad backingColor")

	const h, s, lightness = table.unpack(LuvColor3Utils.fromColor3(color))
	const _, _, backingLightness = table.unpack(LuvColor3Utils.fromColor3(backingColor))
	const contrastedLightness = if backingLightness <= 50
		then math.clamp(lightness + 80, 0, 100)
		else math.clamp(lightness - 80, 0, 100)
	return LuvColor3Utils.toColor3({ h, s, contrastedLightness })
end

return ColorPickerUtils
