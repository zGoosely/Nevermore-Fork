--!strict
--[=[
	A complete HSV color picker with hue, saturation, and value controls.

	@class HSVColorPicker
	@client
]=]

const require = require("../../../Loader").load()

const BaseObject = require("BaseObject")
const Blend = require("Blend")
const HSColorPicker = require("HSColorPicker")
const Maid = require("Maid")
const Observable = require("Observable")
const Signal = require("Signal")
const ValueColorPicker = require("ValueColorPicker")
const ValueObject = require("ValueObject")

const HSVColorPicker = setmetatable({}, BaseObject)
HSVColorPicker.ClassName = "HSVColorPicker"
HSVColorPicker.__index = HSVColorPicker

export type HSVColorPicker =
	typeof(setmetatable(
		{} :: {
			_hsvColorValue: ValueObject.ValueObject<Vector3>,
			_sizeValue: ValueObject.ValueObject<Vector2>,
			_innerPadding: ValueObject.ValueObject<number>,
			_transparency: ValueObject.ValueObject<number>,
			_hueSaturationPicker: HSColorPicker.HSColorPicker,
			_valuePicker: ValueColorPicker.ValueColorPicker,

			ColorChanged: Signal.Signal<(Vector3, Vector3, ...any)>,
			Gui: Frame?,
		},
		{} :: typeof({ __index = HSVColorPicker })
	))
	& BaseObject.BaseObject

--[=[
	Creates a complete HSV color picker.

	```lua
	local picker = HSVColorPicker.new()
	picker:SetColor(Color3.fromRGB(255, 80, 120))
	picker.Gui.Parent = screenGui
	```

	@within HSVColorPicker
	@return HSVColorPicker
]=]
function HSVColorPicker.new(): HSVColorPicker
	const self = setmetatable(BaseObject.new() :: any, HSVColorPicker) :: HSVColorPicker

	self._hsvColorValue = self._maid:Add(ValueObject.new(Vector3.zero, "Vector3"))
	self._sizeValue = self._maid:Add(ValueObject.new(Vector2.new(6, 4), "Vector2"))
	self._innerPadding = self._maid:Add(ValueObject.new(0.2, "number"))
	self._transparency = self._maid:Add(ValueObject.new(0, "number"))
	self._hueSaturationPicker = self._maid:Add(HSColorPicker.new())
	self._valuePicker = self._maid:Add(ValueColorPicker.new())
	self.ColorChanged = self._hsvColorValue.Changed

	self._maid:Add(self:_render():Subscribe(function(gui)
		self.Gui = gui :: Frame
	end))
	self._maid:Add(self._transparency.Changed:Connect(function()
		self._hueSaturationPicker:SetTransparency(self._transparency.Value)
		self._valuePicker:SetTransparency(self._transparency.Value)
	end))

	self._maid:Add(self._hsvColorValue.Changed:Connect(function()
		self._hueSaturationPicker:SetHSVColor(self._hsvColorValue.Value)
		self._valuePicker:SetHSVColor(self._hsvColorValue.Value)
	end))
	self._maid:Add(self._hueSaturationPicker.ColorChanged:Connect(function()
		self._hsvColorValue.Value = self._hueSaturationPicker:GetHSVColor()
	end))
	self._maid:Add(self._valuePicker.ColorChanged:Connect(function()
		self._hsvColorValue.Value = self._valuePicker:GetHSVColor()
	end))

	self._maid:Add(self._hueSaturationPicker:GetSizeValue().Changed:Connect(function()
		self:_updateSize()
	end))
	self._maid:Add(self._valuePicker:GetSizeValue().Changed:Connect(function()
		self:_updateSize()
	end))
	self._maid:Add(self._innerPadding.Changed:Connect(function()
		self:_updateSize()
	end))
	self:_updateSize()

	return self
end

--[=[
	Sets the picker height in line-height units.

	@within HSVColorPicker
	@param height number
]=]
function HSVColorPicker.SetSize(self: HSVColorPicker, height: number): ()
	assert(type(height) == "number" and height >= 0, "Bad height")
	self._hueSaturationPicker:SetSize(height)
	self._valuePicker:SetSize(height)
end

--[=[
	Synchronizes the picker with a Color3Value. Destroy the returned maid to stop
	synchronization.

	@within HSVColorPicker
	@param color3Value Color3Value
	@return Maid
]=]
function HSVColorPicker.SyncValue(self: HSVColorPicker, color3Value: Color3Value): Maid.Maid
	assert(typeof(color3Value) == "Instance" and color3Value:IsA("Color3Value"), "Bad color3Value")
	const maid = Maid.new()
	self:SetColor(color3Value.Value)

	maid:Add(self.ColorChanged:Connect(function()
		color3Value.Value = self:GetColor()
	end))
	maid:Add(color3Value.Changed:Connect(function()
		const currentColor = color3Value.Value
		if currentColor ~= self:GetColor() then
			self:SetColor(currentColor)
		end
	end))

	return maid
end

--[=[
	Hints the surface color behind the picker for automatic contrast.

	@within HSVColorPicker
	@param color Color3
]=]
function HSVColorPicker.HintBackgroundColor(self: HSVColorPicker, color: Color3): ()
	assert(typeof(color) == "Color3", "Bad color")
	self._valuePicker:HintBackgroundColor(color)
end

--[=[
	Sets the selected color as an HSV Vector3.

	@within HSVColorPicker
	@param hsvColor Vector3
]=]
function HSVColorPicker.SetHSVColor(self: HSVColorPicker, hsvColor: Vector3): ()
	assert(typeof(hsvColor) == "Vector3", "Bad hsvColor")
	self._hsvColorValue.Value = hsvColor
end

--[=[
	Returns the selected color as an HSV Vector3.

	@within HSVColorPicker
	@return Vector3
]=]
function HSVColorPicker.GetHSVColor(self: HSVColorPicker): Vector3
	return self._hsvColorValue.Value
end

--[=[
	Sets the selected color.

	@within HSVColorPicker
	@param color Color3
]=]
function HSVColorPicker.SetColor(self: HSVColorPicker, color: Color3): ()
	assert(typeof(color) == "Color3", "Bad color")
	const hue, saturation, value = Color3.toHSV(color)
	self._hsvColorValue.Value = Vector3.new(hue, saturation, value)
end

--[=[
	Returns the selected color.

	@within HSVColorPicker
	@return Color3
]=]
function HSVColorPicker.GetColor(self: HSVColorPicker): Color3
	const current = self._hsvColorValue.Value
	return Color3.fromHSV(current.X, current.Y, current.Z)
end

--[=[
	Returns the picker size value in line-height units.

	@within HSVColorPicker
	@return ValueObject<Vector2>
]=]
function HSVColorPicker.GetSizeValue(self: HSVColorPicker): ValueObject.ValueObject<Vector2>
	return self._sizeValue
end

--[=[
	Returns the picker measurement value.

	@within HSVColorPicker
	@return ValueObject<Vector2>
]=]
function HSVColorPicker.GetMeasureValue(self: HSVColorPicker): ValueObject.ValueObject<Vector2>
	return self._sizeValue
end

--[=[
	Sets the picker transparency.

	@within HSVColorPicker
	@param transparency number
]=]
function HSVColorPicker.SetTransparency(self: HSVColorPicker, transparency: number): ()
	assert(type(transparency) == "number", "Bad transparency")
	self._transparency.Value = math.clamp(transparency, 0, 1)
end

function HSVColorPicker._updateSize(self: HSVColorPicker): ()
	const valueSize = self._valuePicker:GetSizeValue().Value
	const hueSize = self._hueSaturationPicker:GetSizeValue().Value
	self._sizeValue.Value =
		Vector2.new(valueSize.X + hueSize.X + self._innerPadding.Value, math.max(valueSize.Y, hueSize.Y))
end

function HSVColorPicker._render(self: HSVColorPicker): Observable.Observable<Frame>
	const function container(picker: any, anchorPoint: Vector2, position: UDim2): any
		return Blend.New("Frame")({
			AnchorPoint = anchorPoint,
			Position = position,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = Blend.Computed(picker:ObserveIsPressed(), function(isPressed)
				return if isPressed then 2 else 1
			end),

			picker.Gui,
			Blend.New("UIAspectRatioConstraint")({
				AspectRatio = Blend.Computed(picker:GetSizeValue(), function(size: Vector2)
					return if size.X <= 0 or size.Y <= 0 then 1 else size.X / size.Y
				end),
			}),
		})
	end

	return Blend.New("Frame")({
		Name = "HSVColorPicker",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,

		Blend.New("UIAspectRatioConstraint")({
			AspectRatio = Blend.Computed(self._sizeValue, function(size: Vector2)
				return if size.X <= 0 or size.Y <= 0 then 1 else size.X / size.Y
			end),
		}),
		container(self._hueSaturationPicker, Vector2.zero, UDim2.fromScale(0, 0)),
		container(self._valuePicker, Vector2.new(1, 0), UDim2.fromScale(1, 0)),
	}) :: any
end

return HSVColorPicker
