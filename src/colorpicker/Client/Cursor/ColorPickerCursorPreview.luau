--!strict
--[=[
	Floating selected-color preview, primarily for touch input where a finger can
	occlude the picker.

	@class ColorPickerCursorPreview
	@client
]=]

const require = require("../../../Loader").load()

const BasicPane = require("BasicPane")
const BasicPaneUtils = require("BasicPaneUtils")
const Blend = require("Blend")
const ColorPickerUtils = require("ColorPickerUtils")
const LuvColor3Utils = require("LuvColor3Utils")
const MathUtils = require("MathUtils")
const Signal = require("Signal")
const ValueObject = require("ValueObject")

const ColorPickerCursorPreview = setmetatable({}, BasicPane)
ColorPickerCursorPreview.ClassName = "ColorPickerCursorPreview"
ColorPickerCursorPreview.__index = ColorPickerCursorPreview

export type ColorPickerCursorPreview =
	typeof(setmetatable(
		{} :: {
			Gui: Frame?,
			_transparency: ValueObject.ValueObject<number>,
			_backgroundColorHint: ValueObject.ValueObject<Color3>,
			_colorValue: ValueObject.ValueObject<Color3>,
			_heightAbs: ValueObject.ValueObject<number>,
			_offsetAbs: ValueObject.ValueObject<number>,
			_position: ValueObject.ValueObject<Vector2>,

			PositionChanged: Signal.Signal<Vector2>,
		},
		{} :: typeof({ __index = ColorPickerCursorPreview })
	))
	& BasicPane.BasicPane

--[=[
	Creates a cursor preview.

	@within ColorPickerCursorPreview
	@return ColorPickerCursorPreview
]=]
function ColorPickerCursorPreview.new(): ColorPickerCursorPreview
	const self = setmetatable(BasicPane.new() :: any, ColorPickerCursorPreview) :: ColorPickerCursorPreview
	self._backgroundColorHint = self._maid:Add(ValueObject.new(Color3.new(), "Color3"))
	self._heightAbs = self._maid:Add(ValueObject.new(60, "number"))
	self._offsetAbs = self._maid:Add(ValueObject.new(-20, "number"))
	self._position = self._maid:Add(ValueObject.new(Vector2.zero, "Vector2"))
	self._transparency = self._maid:Add(ValueObject.new(0, "number"))
	self._colorValue = self._maid:Add(ValueObject.new(Color3.new(), "Color3"))

	self._maid:Add(self:_render():Subscribe(function(gui)
		self.Gui = gui
	end))
	self.PositionChanged = assert(self._position.Changed :: any, "No PositionChanged signal")
	return self
end

--[=[
	Hints the surface color behind the preview for automatic contrast.

	@within ColorPickerCursorPreview
	@param color Color3
]=]
function ColorPickerCursorPreview.HintBackgroundColor(self: ColorPickerCursorPreview, color: Color3): ()
	assert(typeof(color) == "Color3", "Bad color")
	self._backgroundColorHint.Value = color
end

--[=[
	Sets the preview's normalized picker position.

	@within ColorPickerCursorPreview
	@param position Vector2
]=]
function ColorPickerCursorPreview.SetPosition(self: ColorPickerCursorPreview, position: Vector2): ()
	assert(typeof(position) == "Vector2", "Bad position")
	self._position.Value = position
end

--[=[
	Returns the preview's normalized picker position.

	@within ColorPickerCursorPreview
	@return Vector2
]=]
function ColorPickerCursorPreview.GetPosition(self: ColorPickerCursorPreview): Vector2
	return self._position.Value
end

--[=[
	Sets the color shown in the preview.

	@within ColorPickerCursorPreview
	@param color Color3
]=]
function ColorPickerCursorPreview.SetColor(self: ColorPickerCursorPreview, color: Color3): ()
	assert(typeof(color) == "Color3", "Bad color")
	self._colorValue.Value = color
end

--[=[
	Sets preview transparency.

	@within ColorPickerCursorPreview
	@param transparency number
]=]
function ColorPickerCursorPreview.SetTransparency(self: ColorPickerCursorPreview, transparency: number): ()
	assert(type(transparency) == "number", "Bad transparency")
	self._transparency.Value = math.clamp(transparency, 0, 1)
end

function ColorPickerCursorPreview._render(self: ColorPickerCursorPreview): any
	const percentVisible = Blend.Spring(BasicPaneUtils.observePercentVisible(self), 30, 0.5)
	const transparencyTarget = Blend.Computed(
		BasicPaneUtils.observePercentVisible(self),
		self._transparency,
		function(visible, transparency)
			return MathUtils.map(visible, 0, 1, 1, transparency)
		end
	)
	const transparency = Blend.Spring(transparencyTarget, 30)
	const isOutlineVisible = Blend.Computed(self._colorValue, self._backgroundColorHint, function(color, backingColor)
		const _, _, lightness = table.unpack(LuvColor3Utils.fromColor3(color))
		const _, _, backingLightness = table.unpack(LuvColor3Utils.fromColor3(backingColor))
		return math.abs(backingLightness - lightness) <= 60
	end)

	return Blend.New("Frame")({
		Name = "ColorPickerCursorPreview",
		BackgroundTransparency = 1,
		Size = Blend.Computed(self._heightAbs, function(heightAbs)
			return UDim2.fromOffset(heightAbs, heightAbs)
		end),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = Blend.Computed(
			self._position,
			self._offsetAbs,
			self._heightAbs,
			function(position: Vector2, offsetAbs: number, heightAbs: number)
				return UDim2.new(position.X, 0, position.Y, offsetAbs - heightAbs / 2)
			end
		),
		ZIndex = 3,

		Blend.New("UIAspectRatioConstraint")({ AspectRatio = 1 }),
		Blend.New("Frame")({
			BackgroundTransparency = transparency,
			BackgroundColor3 = self._colorValue,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),

			Blend.New("UIScale")({ Scale = percentVisible }),
			Blend.New("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			Blend.New("UIStroke")({
				Color = Blend.Spring(
					Blend.Computed(
						self._colorValue,
						self._backgroundColorHint,
						isOutlineVisible,
						function(color, backingColor, needed)
							return if needed
								then ColorPickerUtils.getOutlineWithContrast(color, backingColor)
								else color
						end
					),
					20
				),
				Transparency = transparency,
				Thickness = Blend.Computed(percentVisible, function(percent: number)
					return percent * 3
				end),
			}),
		}),
	})
end

return ColorPickerCursorPreview
