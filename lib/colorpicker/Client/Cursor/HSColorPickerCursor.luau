--!strict
--[=[
	Crosshair cursor used by HSColorPicker.

	@class HSColorPickerCursor
	@client
]=]

const require = require("../../../Loader").load()

const BaseObject = require("BaseObject")
const Blend = require("Blend")
const ColorPickerUtils = require("ColorPickerUtils")
const Observable = require("Observable")
const Signal = require("Signal")
const ValueObject = require("ValueObject")

const HSColorPickerCursor = setmetatable({}, BaseObject)
HSColorPickerCursor.ClassName = "HSColorPickerCursor"
HSColorPickerCursor.__index = HSColorPickerCursor

export type HSColorPickerCursor =
	typeof(setmetatable(
		{} :: {
			Gui: Frame?,
			_backgroundColorHint: ValueObject.ValueObject<Color3>,
			_height: ValueObject.ValueObject<number>,
			_crossHairWidthAbs: ValueObject.ValueObject<number>,
			_verticalHairVisible: ValueObject.ValueObject<boolean>,
			_horizontalHairVisible: ValueObject.ValueObject<boolean>,
			_position: ValueObject.ValueObject<Vector2>,
			_transparency: ValueObject.ValueObject<number>,
			PositionChanged: Signal.Signal<Vector2>,
		},
		{} :: typeof({ __index = HSColorPickerCursor })
	))
	& BaseObject.BaseObject

--[=[
	Creates a crosshair cursor.

	@within HSColorPickerCursor
	@return HSColorPickerCursor
]=]
function HSColorPickerCursor.new(): HSColorPickerCursor
	const self = setmetatable(BaseObject.new() :: any, HSColorPickerCursor) :: HSColorPickerCursor
	self._backgroundColorHint = self._maid:Add(ValueObject.new(Color3.new(), "Color3"))
	self._height = self._maid:Add(ValueObject.new(0.075, "number"))
	self._crossHairWidthAbs = self._maid:Add(ValueObject.new(1, "number"))
	self._verticalHairVisible = self._maid:Add(ValueObject.new(true, "boolean"))
	self._horizontalHairVisible = self._maid:Add(ValueObject.new(true, "boolean"))
	self._position = self._maid:Add(ValueObject.new(Vector2.zero, "Vector2"))
	self._transparency = self._maid:Add(ValueObject.new(0, "number"))

	self._maid:Add(self:_render():Subscribe(function(gui)
		self.Gui = gui
	end))
	self.PositionChanged = assert(self._position.Changed :: any, "No PositionChanged signal")
	return self
end

--[=[
	Hints the color beneath the cursor for automatic contrast.

	@within HSColorPickerCursor
	@param color Color3
]=]
function HSColorPickerCursor.HintBackgroundColor(self: HSColorPickerCursor, color: Color3): ()
	assert(typeof(color) == "Color3", "Bad color")
	self._backgroundColorHint.Value = color
end

--[=[
	Controls vertical crosshair visibility.

	@within HSColorPickerCursor
	@param visible boolean
]=]
function HSColorPickerCursor.SetVerticalHairVisible(self: HSColorPickerCursor, visible: boolean): ()
	assert(type(visible) == "boolean", "Bad visible")
	self._verticalHairVisible.Value = visible
end

--[=[
	Controls horizontal crosshair visibility.

	@within HSColorPickerCursor
	@param visible boolean
]=]
function HSColorPickerCursor.SetHorizontalHairVisible(self: HSColorPickerCursor, visible: boolean): ()
	assert(type(visible) == "boolean", "Bad visible")
	self._horizontalHairVisible.Value = visible
end

--[=[
	Sets cursor height in scale units.

	@within HSColorPickerCursor
	@param height number
]=]
function HSColorPickerCursor.SetHeight(self: HSColorPickerCursor, height: number): ()
	assert(type(height) == "number" and height >= 0, "Bad height")
	self._height.Value = height
end

--[=[
	Sets the normalized cursor position.

	@within HSColorPickerCursor
	@param position Vector2
]=]
function HSColorPickerCursor.SetPosition(self: HSColorPickerCursor, position: Vector2): ()
	assert(typeof(position) == "Vector2", "Bad position")
	self._position.Value = position
end

--[=[
	Returns the normalized cursor position.

	@within HSColorPickerCursor
	@return Vector2
]=]
function HSColorPickerCursor.GetPosition(self: HSColorPickerCursor): Vector2
	return self._position.Value
end

--[=[
	Sets cursor transparency.

	@within HSColorPickerCursor
	@param transparency number
]=]
function HSColorPickerCursor.SetTransparency(self: HSColorPickerCursor, transparency: number): ()
	assert(type(transparency) == "number", "Bad transparency")
	self._transparency.Value = math.clamp(transparency, 0, 1)
end

function HSColorPickerCursor._render(self: HSColorPickerCursor): Observable.Observable<Frame>
	const outlineColor = Blend.Computed(self._backgroundColorHint, function(backingColor)
		return ColorPickerUtils.getOutlineWithContrast(Color3.new(), backingColor)
	end)
	return Blend.New("Frame")({
		Name = "HSColorPickerCursor",
		Size = Blend.Computed(self._height, function(height)
			return UDim2.fromScale(height, height)
		end),
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = Blend.Computed(self._position, function(position)
			return UDim2.fromScale(position.X, position.Y)
		end),

		Blend.New("UIAspectRatioConstraint")({ AspectRatio = 1 }),
		Blend.New("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Visible = self._horizontalHairVisible,
			Size = Blend.Computed(self._crossHairWidthAbs, function(width)
				return UDim2.new(1, 0, 0, width)
			end),
			BackgroundColor3 = outlineColor,
			BackgroundTransparency = self._transparency,
			Blend.New("UICorner")({ CornerRadius = UDim.new(1, 0) }),
		}),
		Blend.New("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Visible = self._verticalHairVisible,
			Size = Blend.Computed(self._crossHairWidthAbs, function(width)
				return UDim2.new(0, width, 1, 0)
			end),
			BackgroundColor3 = Blend.Spring(outlineColor, 20),
			BackgroundTransparency = self._transparency,
			Blend.New("UICorner")({ CornerRadius = UDim.new(1, 0) }),
		}),
	}) :: any
end

return HSColorPickerCursor
