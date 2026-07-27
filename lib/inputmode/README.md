# InputMode

`InputModeServiceClient` classifies local Roblox input without reducing the
player to a device or platform. A keyboard, mouse, touch surface, and gamepad can
all be connected at once; the package tracks which input family was used most
recently.

This package is client-only and performs no networking. Use
`PlayerInputModeService` when the server or other clients need to know a player's
current control family.

## Setup

Register the service before initializing the client ServiceBag:

```luau
const InputModeServiceClient = require("InputModeServiceClient")
const ServiceBag = require("ServiceBag")

local serviceBag = ServiceBag.new()
local inputModes = serviceBag:GetService(InputModeServiceClient)

serviceBag:Init()
serviceBag:Start()
```

The service handles `InputBegan`, `InputChanged`, and `InputEnded`. Mouse movement
is filtered to avoid false mode changes, and thumbsticks use a deadzone.

## Common use cases

InputMode is useful whenever local presentation or controls should follow what
the player is actively using:

- Swap keyboard keys, gamepad buttons, and touch icons in interaction prompts.
- Show touch controls only after touch becomes the active input family.
- Enable Roblox gamepad selection when the player returns to a controller.
- Handle hybrid devices without permanently classifying them as mobile or PC.
- Change control instructions between WASD, arrow keys, D-pad, or a custom group.
- Measure which local control scheme is being used during a tutorial step.

For example, one selector can coordinate prompt legends, touch controls, and
gamepad UI focus:

```luau
const GuiService = game:GetService("GuiService")
const InputModeTypeSelector = require("InputModeTypeSelector")
const InputModeTypes = require("InputModeTypes")

local selector = maid:Add(InputModeTypeSelector.new(serviceBag, {
	InputModeTypes.Gamepads,
	InputModeTypes.KeyboardAndMouse,
	InputModeTypes.Touch,
}))

selector:Bind(function(activeMode, modeMaid)
	keyboardPrompt.Visible = activeMode == InputModeTypes.KeyboardAndMouse
	gamepadPrompt.Visible = activeMode == InputModeTypes.Gamepads
	touchControls.Visible = activeMode == InputModeTypes.Touch

	if activeMode == InputModeTypes.Gamepads then
		GuiService.SelectedObject = firstGamepadButton
		modeMaid:Add(function()
			if GuiService.SelectedObject == firstGamepadButton then
				GuiService.SelectedObject = nil
			end
		end)
	end
end)
```

Use local InputMode instead of PlayerInputMode when no server or other client
needs the result; it avoids networking and exposes more specific modes.

## Watching one mode

`GetInputMode()` returns shared runtime state for a static definition from
`InputModeTypes`:

```luau
const InputModeTypes = require("InputModeTypes")

local touch = inputModes:GetInputMode(InputModeTypes.Touch)

maid:Add(touch.Enabled:Connect(function()
	print("Touch was just used")
end))

print(touch:GetLastEnabledTime())
```

Useful predefined definitions include:

- `Keyboard`, `Mouse`, and `KeyboardAndMouse`
- `Touch`
- `Gamepads`, `DPad`, and `Thumbsticks`
- `WASD`, `ArrowKeys`, and `Keypad`

`Enabled` means the mode was used; it does not mean that it is the only connected
input method.

## Selecting the most recently used mode

Use `InputModeTypeSelector` when UI or controls should switch between a known set
of modes:

```luau
const InputModeTypeSelector = require("InputModeTypeSelector")
const InputModeTypes = require("InputModeTypes")

local selector = maid:Add(InputModeTypeSelector.new(serviceBag, {
	InputModeTypes.Gamepads,
	InputModeTypes.KeyboardAndMouse,
	InputModeTypes.Touch,
}))

selector:Bind(function(activeMode, modeMaid)
	if activeMode == InputModeTypes.Gamepads then
		print("Show gamepad button prompts")
	elseif activeMode == InputModeTypes.Touch then
		print("Show touch controls")
	elseif activeMode == InputModeTypes.KeyboardAndMouse then
		print("Show keyboard controls")
	end

	-- Tasks placed in modeMaid are cleaned when the active mode changes.
end)
```

You can also use:

```luau
print(selector.Value)
print(selector:GetActiveInputType())

maid:Add(selector:ObserveActiveInputType():Subscribe(function(activeMode)
	print("Active input mode", activeMode and activeMode.Name)
end))

maid:Add(selector:ObserveIsActive(InputModeTypes.Touch):Subscribe(function(isTouch)
	print("Touch is active", isTouch)
end))
```

## Custom modes

Definitions may contain Roblox input enums, strings used by your own binding
system, or other definitions:

```luau
const InputModeType = require("InputModeType")

local CombatKeyboard = InputModeType.new("CombatKeyboard", {
	Enum.KeyCode.Q,
	Enum.KeyCode.E,
	Enum.KeyCode.R,
})

local combatKeyboardState = inputModes:GetInputMode(CombatKeyboard)
maid:Add(combatKeyboardState.Enabled:Connect(function()
	print("A combat keyboard key was used")
end))
```

Adding the mode through `GetInputMode()` automatically includes it in input
processing. Destroy selectors and disconnect `Enabled` subscriptions through a
Maid when their UI or controller is removed.
