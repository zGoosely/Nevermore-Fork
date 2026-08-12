# ColorPicker

`ColorPicker` provides client-side HSV color controls built with Blend. The
package creates its own GUI, supports mouse and touch dragging, exposes the
selected color as both `Color3` and HSV, and automatically chooses contrasting
cursor colors.

The package is visual and client-only. It does not replicate color selections;
send a finalized color through your own validated networking when the server
needs it.

## Complete picker

`HSVColorPicker` combines the square hue/saturation control with the vertical
value control:

```luau
const HSVColorPicker = require("HSVColorPicker")
const Maid = require("Maid")

local maid = Maid.new()
local picker = maid:Add(HSVColorPicker.new())

picker:SetColor(Color3.fromRGB(255, 80, 120))
picker:SetSize(5)
picker:HintBackgroundColor(panel.BackgroundColor3)

local gui = assert(picker.Gui)
gui.Size = UDim2.fromOffset(360, 240)
gui.Position = UDim2.fromScale(0.5, 0.5)
gui.AnchorPoint = Vector2.new(0.5, 0.5)
gui.Parent = panel

maid:Add(picker.ColorChanged:Connect(function()
	local color = picker:GetColor()
	local hsv = picker:GetHSVColor()

	preview.BackgroundColor3 = color
	print("HSV", hsv.X, hsv.Y, hsv.Z)
end))
```

`SetSize()` controls the picker's internal aspect ratio in line-height units.
The parent still controls its actual pixel or scale size through `picker.Gui`.

Destroy the picker directly or own it with a `Maid`. Destruction removes the
generated GUI, input connections, observables, and child controls.

## Synchronizing a Color3Value

`SyncValue()` provides two-way synchronization with a `Color3Value`:

```luau
local picker = maid:Add(HSVColorPicker.new())
local selectedColor = Instance.new("Color3Value")
selectedColor.Value = Color3.fromRGB(60, 170, 255)

maid:Add(picker:SyncValue(selectedColor))

-- Either side updates the other.
selectedColor.Value = Color3.fromRGB(255, 210, 70)
picker:SetColor(Color3.fromRGB(100, 255, 140))
```

The returned `Maid` owns only the synchronization connections. Destroying it
stops synchronization without destroying the picker or the `Color3Value`.

## Individual controls

Use the smaller controls when building a custom layout:

- `HSColorPicker` selects hue and saturation while preserving the current HSV
  value component.
- `ValueColorPicker` selects the value component while preserving hue and
  saturation.

```luau
const HSColorPicker = require("HSColorPicker")
const ValueColorPicker = require("ValueColorPicker")

local hsPicker = maid:Add(HSColorPicker.new())
local valuePicker = maid:Add(ValueColorPicker.new())

local function synchronizeFrom(source)
	local hsv = source:GetHSVColor()
	hsPicker:SetHSVColor(hsv)
	valuePicker:SetHSVColor(hsv)
	preview.BackgroundColor3 = Color3.fromHSV(hsv.X, hsv.Y, hsv.Z)
end

maid:Add(hsPicker.ColorChanged:Connect(function()
	synchronizeFrom(hsPicker)
end))

maid:Add(valuePicker.ColorChanged:Connect(function()
	synchronizeFrom(valuePicker)
end))
```

For most interfaces, prefer `HSVColorPicker`; it already performs this
synchronization and handles the layout and drag priority.

## Transparency and contrast

`SetTransparency()` fades the picker visuals without disabling input:

```luau
picker:SetTransparency(0.35)
picker:HintBackgroundColor(Color3.fromRGB(20, 22, 28))
```

`HintBackgroundColor()` is a visual hint. It lets the marker and preview pick a
light or dark outline that remains readable against the containing panel. It
does not change the selected color.

## Lower-level children

The package also exports implementation components for specialized controls:

- `ButtonDragModel` converts mouse and touch input over a `GuiButton` into a
  normalized `Vector2`, drag delta, and pressed-state observable.
- `HSColorPickerCursor` renders the hue/saturation crosshair.
- `ColorPickerCursorPreview` renders the floating selected-color preview shown
  while dragging.
- `ColorPickerTriangle` renders the marker beside the value strip.
- `ColorPickerUtils.getOutlineWithContrast()` chooses a perceptually
  contrasting outline using HSLuv color space.
- `LuvColor3Utils` converts, interpolates, darkens, and desaturates colors in
  HSLuv color space.

These children are public building blocks, but normal consumers only need
`HSVColorPicker`.

## Server validation

Treat every client-selected color as untrusted input. If players submit colors
to the server, validate that the payload is a `Color3` and apply any game rules
there, such as palette restrictions, ownership checks, or rate limits.
