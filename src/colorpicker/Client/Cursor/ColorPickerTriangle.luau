--!strict
--[=[
	Contrast-aware triangular marker used by value pickers.

	@class ColorPickerTriangle
	@client
]=]

const require = require("../../../Loader").load()

const BaseObject = require("BaseObject")
const Blend = require("Blend")
const ColorPickerUtils = require("ColorPickerUtils")
const Observable = require("Observable")
const ValueObject = require("ValueObject")

const ColorPickerTriangle = setmetatable({}, BaseObject)
ColorPickerTriangle.ClassName = "ColorPickerTriangle"
ColorPickerTriangle.__index = ColorPickerTriangle

export type ColorPickerTriangle =
	typeof(setmetatable(
		{} :: {
			Gui: Frame?,
			_transparency: ValueObject.ValueObject<number>,
			_backgroundColorHint: ValueObject.ValueObject<Color3>,
			_color: ValueObject.ValueObject<Color3>,
			_sizeValue: ValueObject.ValueObject<Vector2>,
		},
		{} :: typeof({ __index = ColorPickerTriangle })
	))
	& BaseObject.BaseObject

--[=[
	Creates a triangular marker.

	@within ColorPickerTriangle
	@return ColorPickerTriangle
]=]
function ColorPickerTriangle.new(): ColorPickerTriangle
	const self = setmetatable(BaseObject.new() :: any, ColorPickerTriangle) :: ColorPickerTriangle
	self._transparency = self._maid:Add(ValueObject.new(0, "number"))
	self._backgroundColorHint = self._maid:Add(ValueObject.new(Color3.new(), "Color3"))
	self._color = self._maid:Add(ValueObject.new(Color3.new(1, 1, 1), "Color3"))
	self._sizeValue = self._maid:Add(ValueObject.new(Vector2.new(0.05, 0.1), "Vector2"))

	self._maid:Add(self:_render():Subscribe(function(gui)
		self.Gui = gui
	end))
	return self
end

--[=[
	Hints the surface color behind the marker for automatic contrast.

	@within ColorPickerTriangle
	@param color Color3
]=]
function ColorPickerTriangle.HintBackgroundColor(self: ColorPickerTriangle, color: Color3): ()
	assert(typeof(color) == "Color3", "Bad color")
	self._backgroundColorHint.Value = color
end

--[=[
	Returns the marker's sizing value.

	@within ColorPickerTriangle
	@return ValueObject<Vector2>
]=]
function ColorPickerTriangle.GetSizeValue(self: ColorPickerTriangle): ValueObject.ValueObject<Vector2>
	return self._sizeValue
end

--[=[
	Returns the marker's measurement value.

	@within ColorPickerTriangle
	@return ValueObject<Vector2>
]=]
function ColorPickerTriangle.GetMeasureValue(self: ColorPickerTriangle): ValueObject.ValueObject<Vector2>
	return self._sizeValue
end

--[=[
	Sets the marker color before contrast adjustment.

	@within ColorPickerTriangle
	@param color Color3
]=]
function ColorPickerTriangle.SetColor(self: ColorPickerTriangle, color: Color3): ()
	assert(typeof(color) == "Color3", "Bad color")
	self._color.Value = color
end

--[=[
	Sets marker transparency.

	@within ColorPickerTriangle
	@param transparency number
]=]
function ColorPickerTriangle.SetTransparency(self: ColorPickerTriangle, transparency: number): ()
	assert(type(transparency) == "number", "Bad transparency")
	self._transparency.Value = math.clamp(transparency, 0, 1)
end

function ColorPickerTriangle._render(self: ColorPickerTriangle): Observable.Observable<Frame>
	return Blend.New("Frame")({
		Name = "ColorPickerTriangle",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,

		Blend.New("ImageLabel")({
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ImageColor3 = Blend.Computed(self._color, self._backgroundColorHint, function(color, backingColor)
				return ColorPickerUtils.getOutlineWithContrast(color, backingColor)
			end),
			ImageTransparency = self._transparency,
			Image = "rbxassetid://9291514809",
		}),

		Blend.New("UIAspectRatioConstraint")({
			AspectRatio = Blend.Computed(self._sizeValue, function(size)
				return if size.X <= 0 or size.Y <= 0 then 1 else size.X / size.Y
			end),
		}),
	}) :: any
end

return ColorPickerTriangle
