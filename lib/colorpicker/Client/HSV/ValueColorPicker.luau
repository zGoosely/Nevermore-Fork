--!strict
--[=[
	Selects the value component of an HSV color.

	@class ValueColorPicker
	@client
]=]

const require = require("../../../Loader").load()

const BaseObject = require("BaseObject")
const Blend = require("Blend")
const ButtonDragModel = require("ButtonDragModel")
const ColorPickerCursorPreview = require("ColorPickerCursorPreview")
const ColorPickerTriangle = require("ColorPickerTriangle")
const Observable = require("Observable")
const Signal = require("Signal")
const ValueObject = require("ValueObject")

const ValueColorPicker = setmetatable({}, BaseObject)
ValueColorPicker.ClassName = "ValueColorPicker"
ValueColorPicker.__index = ValueColorPicker

export type ValueColorPicker =
	typeof(setmetatable(
		{} :: {
			_hsvColorValue: ValueObject.ValueObject<Vector3>,
			_backgroundColorHint: ValueObject.ValueObject<Color3>,
			_sizeValue: ValueObject.ValueObject<Vector2>,
			_leftWidth: ValueObject.ValueObject<number>,
			_transparency: ValueObject.ValueObject<number>,
			_dragModel: ButtonDragModel.ButtonDragModel,
			_triangle: ColorPickerTriangle.ColorPickerTriangle,
			_preview: ColorPickerCursorPreview.ColorPickerCursorPreview,

			ColorChanged: Signal.Signal<(Vector3, Vector3, ...any)>,
			Gui: ImageButton?,
		},
		{} :: typeof({ __index = ValueColorPicker })
	))
	& BaseObject.BaseObject

--[=[
	Creates an HSV value picker.

	@within ValueColorPicker
	@return ValueColorPicker
]=]
function ValueColorPicker.new(): ValueColorPicker
	const self = setmetatable(BaseObject.new() :: any, ValueColorPicker) :: ValueColorPicker

	self._hsvColorValue = self._maid:Add(ValueObject.new(Vector3.zero, "Vector3"))
	self._backgroundColorHint = self._maid:Add(ValueObject.new(Color3.new(), "Color3"))
	self._sizeValue = self._maid:Add(ValueObject.new(Vector2.new(0, 4), "Vector2"))
	self._leftWidth = self._maid:Add(ValueObject.new(0.25, "number"))
	self._transparency = self._maid:Add(ValueObject.new(0, "number"))
	self._dragModel = self._maid:Add(ButtonDragModel.new())
	self._dragModel:SetClampWithinButton(true)
	self.ColorChanged = self._hsvColorValue.Changed

	self._triangle = self._maid:Add(ColorPickerTriangle.new())
	const triangleGui = assert(self._triangle.Gui, "No triangle Gui")
	triangleGui.AnchorPoint = Vector2.new(0, 0.5)
	triangleGui.Position = UDim2.fromScale(0, 1)
	self._preview = self._maid:Add(ColorPickerCursorPreview.new())

	self._maid:Add(self:_render():Subscribe(function(gui)
		self.Gui = gui :: ImageButton
	end))
	self._maid:Add(self._transparency.Changed:Connect(function()
		self._preview:SetTransparency(self._transparency.Value)
		self._triangle:SetTransparency(self._transparency.Value)
	end))

	self._maid:Add(self._dragModel.DragPositionChanged:Connect(function()
		const position = self._dragModel:GetDragPosition()
		if not position then
			return
		end

		const current = self._hsvColorValue.Value
		self._hsvColorValue.Value = Vector3.new(current.X, current.Y, 1 - position.Y)
		const gui = self._triangle.Gui
		if gui then
			gui.Position = UDim2.fromScale(0, position.Y)
		end
	end))
	self._maid:Add(self._hsvColorValue.Changed:Connect(function()
		const gui = self._triangle.Gui
		if gui then
			gui.Position = UDim2.fromScale(0, 1 - self._hsvColorValue.Value.Z)
		end
	end))

	self._maid:Add(self._dragModel:ObserveIsPressed():Subscribe(function(isDragging)
		self._preview:SetVisible(isDragging)
	end))
	self._maid:Add(self._hsvColorValue.Changed:Connect(function()
		self:_updatePreviewPosition()
		self:_updateHintedColors()
	end))
	self:_updatePreviewPosition()
	self:_updateHintedColors()

	self._maid:Add(self._backgroundColorHint.Changed:Connect(function()
		self._triangle:HintBackgroundColor(self._backgroundColorHint.Value)
	end))
	self._triangle:HintBackgroundColor(self._backgroundColorHint.Value)

	self._maid:Add(self._triangle:GetSizeValue().Changed:Connect(function()
		self:_updateSize()
	end))
	self._maid:Add(self._leftWidth.Changed:Connect(function()
		self:_updateSize()
	end))
	self:_updateSize()

	return self
end

--[=[
	Sets the picker height in line-height units.

	@within ValueColorPicker
	@param height number
]=]
function ValueColorPicker.SetSize(self: ValueColorPicker, height: number): ()
	assert(type(height) == "number" and height >= 0, "Bad height")
	self:_updateSize(height)
end

--[=[
	Hints the surface color behind the picker for automatic contrast.

	@within ValueColorPicker
	@param color Color3
]=]
function ValueColorPicker.HintBackgroundColor(self: ValueColorPicker, color: Color3): ()
	assert(typeof(color) == "Color3", "Bad color")
	self._backgroundColorHint.Value = color
end

--[=[
	Observes whether the picker is currently pressed.

	@within ValueColorPicker
	@return Observable<boolean>
]=]
function ValueColorPicker.ObserveIsPressed(self: ValueColorPicker): Observable.Observable<boolean>
	return self._dragModel:ObserveIsPressed()
end

--[=[
	Sets the selected color as an HSV Vector3.

	@within ValueColorPicker
	@param hsvColor Vector3
]=]
function ValueColorPicker.SetHSVColor(self: ValueColorPicker, hsvColor: Vector3): ()
	assert(typeof(hsvColor) == "Vector3", "Bad hsvColor")
	self._hsvColorValue.Value = hsvColor
end

--[=[
	Returns the selected color as an HSV Vector3.

	@within ValueColorPicker
	@return Vector3
]=]
function ValueColorPicker.GetHSVColor(self: ValueColorPicker): Vector3
	return self._hsvColorValue.Value
end

--[=[
	Sets the selected color.

	@within ValueColorPicker
	@param color Color3
]=]
function ValueColorPicker.SetColor(self: ValueColorPicker, color: Color3): ()
	assert(typeof(color) == "Color3", "Bad color")
	const hue, saturation, value = Color3.toHSV(color)
	self._hsvColorValue.Value = Vector3.new(hue, saturation, value)
end

--[=[
	Returns the selected color.

	@within ValueColorPicker
	@return Color3
]=]
function ValueColorPicker.GetColor(self: ValueColorPicker): Color3
	const current = self._hsvColorValue.Value
	return Color3.fromHSV(current.X, current.Y, current.Z)
end

--[=[
	Returns the picker size value in line-height units.

	@within ValueColorPicker
	@return ValueObject<Vector2>
]=]
function ValueColorPicker.GetSizeValue(self: ValueColorPicker): ValueObject.ValueObject<Vector2>
	return self._sizeValue
end

--[=[
	Returns the picker measurement value.

	@within ValueColorPicker
	@return ValueObject<Vector2>
]=]
function ValueColorPicker.GetMeasureValue(self: ValueColorPicker): ValueObject.ValueObject<Vector2>
	return self._sizeValue
end

--[=[
	Sets the picker transparency.

	@within ValueColorPicker
	@param transparency number
]=]
function ValueColorPicker.SetTransparency(self: ValueColorPicker, transparency: number): ()
	assert(type(transparency) == "number", "Bad transparency")
	self._transparency.Value = math.clamp(transparency, 0, 1)
end

function ValueColorPicker._updatePreviewPosition(self: ValueColorPicker): ()
	self._preview:SetPosition(Vector2.new(0.5, 1 - self._hsvColorValue.Value.Z))
end

function ValueColorPicker._updateSize(self: ValueColorPicker, newHeight: number?): ()
	const triangleSize = self._triangle:GetSizeValue().Value
	const width = self._leftWidth.Value + triangleSize.Y
	const height = newHeight or self._sizeValue.Value.Y
	self._sizeValue.Value = Vector2.new(width, height)
end

function ValueColorPicker._updateHintedColors(self: ValueColorPicker): ()
	const current = self._hsvColorValue.Value
	const color = Color3.fromHSV(current.X, current.Y, current.Z)
	self._preview:HintBackgroundColor(color)
	self._preview:SetColor(color)
end

function ValueColorPicker._render(self: ValueColorPicker): Observable.Observable<ImageButton>
	return Blend.New("ImageButton")({
		Name = "ValueColorPicker",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = true,

		[Blend.Instance] = function(instance)
			self._dragModel:SetButton(instance)
		end,

		Blend.New("UIAspectRatioConstraint")({
			AspectRatio = Blend.Computed(self._sizeValue, function(size: Vector2)
				return if size.X <= 0 or size.Y <= 0 then 1 else size.X / size.Y
			end),
		}),
		Blend.New("Frame")({
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = self._transparency,
			Size = Blend.Computed(self._leftWidth, self._sizeValue, function(width: number, size: Vector2)
				return if size.X == 0 then UDim2.fromScale(0, 1) else UDim2.fromScale(width / size.X, 1)
			end),

			Blend.New("UIGradient")({
				Color = Blend.Computed(self._hsvColorValue, function(color: Vector3)
					const hue, saturation = color.X, color.Y
					return ColorSequence.new(Color3.fromHSV(hue, saturation, 0), Color3.fromHSV(hue, saturation, 1))
				end),
				Rotation = -90,
			}),
			Blend.New("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			self._preview.Gui,
		}),
		Blend.New("Frame")({
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(1, 0),
			AnchorPoint = Vector2.new(1, 0),
			Size = Blend.Computed(self._leftWidth, self._sizeValue, function(width: number, size: Vector2)
				return if size.X == 0 then UDim2.fromScale(0, 1) else UDim2.fromScale((size.X - width) / size.X, 1)
			end),

			self._triangle.Gui,
		}),
	}) :: any
end

return ValueColorPicker
