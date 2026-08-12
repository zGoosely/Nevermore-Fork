# InputKeyMapUtils

`InputKeyMapUtils` provides structured, cross-platform key mappings and keybinding management for Nevermore.

It lets a game describe an action once and associate that action with different inputs for:

- Keyboard and mouse
- Gamepad
- Touch and mobile controls
- Slotted touch buttons
- Custom input chords

For example, one `"INTERACT"` action can represent all of these bindings:

```text
INTERACT
├── Keyboard & Mouse: E
├── Gamepad: ButtonX
└── Touch: primary2
```

The package also supports:

- Rebindable actions
- Observing binding changes
- Observing the active input device
- Centralized input providers
- Global provider registration
- `ProximityPrompt` configuration
- UI hints through `InputImageLibrary`

> [!IMPORTANT]
> `InputKeyMapUtils` stores and observes binding data. It does not execute gameplay actions or bind inputs by itself.
>
> Use the resulting input types with a separate input system such as `ContextActionService`, `UserInputService`, or a custom action controller.

## Installation

```bash
npm install @quenty/inputkeymaputils --save
```

For input icons:

```bash
npm install @quenty/sprites --save
```

Depending on how your Nevermore packages are configured, `InputImageLibrary` may already be available through the sprites package.

## Architecture

The general flow is:

```text
InputKeyMapListProvider
        │
        ├── JUMP
        ├── INTERACT
        └── SPRINT
              │
              ▼
      InputKeyMapList
              │
              ├── KeyboardAndMouse InputKeyMap
              ├── Gamepads InputKeyMap
              └── Touch InputKeyMap
                      │
                      ▼
       Input keys, chords, or touch slots
```

At runtime, consumers can use the stored data for:

```text
InputKeyMapList
        │
        ├── Gameplay binding
        │       └── ContextActionService
        │
        ├── Input hint UI
        │       └── InputImageLibrary
        │
        ├── Roblox prompts
        │       └── ProximityPromptInputUtils
        │
        └── Settings and rebinding
                └── Observe keymap changes
```

## Core Types

### `InputKeyMap`

Represents the bindings for one input mode.

For example:

```luau
InputKeyMap.new(InputModeTypes.KeyboardAndMouse, {
	Enum.KeyCode.E,
})
```

This means:

> The keyboard-and-mouse binding for this action is `E`.

Another map can describe the gamepad binding:

```luau
InputKeyMap.new(InputModeTypes.Gamepads, {
	Enum.KeyCode.ButtonX,
})
```

An `InputKeyMap` may contain more than one input:

```luau
InputKeyMap.new(InputModeTypes.KeyboardAndMouse, {
	Enum.KeyCode.LeftShift,
	Enum.KeyCode.RightShift,
})
```

Both keys can then represent the same action.

---

### `InputKeyMapList`

Groups the maps for every supported input mode into one named gameplay action.

```text
InputKeyMapList: INTERACT
├── KeyboardAndMouse → E
├── Gamepads         → ButtonX
└── Touch            → primary2
```

It also stores action metadata such as:

- The internal list name
- The player-facing binding name
- Whether the action may be rebound

---

### `InputKeyMapListProvider`

Defines and owns a collection of related actions.

A general gameplay provider might contain:

```text
General
├── JUMP
├── INTERACT
├── SPRINT
└── CROUCH
```

A weapon provider might contain:

```text
Weapon
├── FIRE
├── AIM
├── RELOAD
├── MELEE
└── INSPECT
```

Providers make it possible for several systems to retrieve the same action definitions without constructing duplicate keymaps.

---

### `InputKeyMapRegistryServiceShared`

Tracks active `InputKeyMapListProvider` instances.

This allows other systems to discover providers globally, which is useful for:

- Controls menus
- Keybinding settings
- Saving player bindings
- Restoring defaults
- Finding action definitions across packages
- Detecting conflicting bindings

---

### `InputKeyMapServiceClient`

Initializes the client-side keymap environment.

It manages client-specific behavior such as:

- Input-mode subscriptions
- Localization support
- Client-side keymap registration
- Active input observation

---

### `InputKeyMapService`

Initializes shared and server-side keymap services.

The server generally does not read raw local player input. Its role is to initialize the shared registry and related infrastructure used by the keymap system.

## Service Setup

### Server

Initialize `InputKeyMapService` from your server service loader:

```luau
--!strict

local require = require("@game/ReplicatedStorage/Packages/Nevermore/Loader").load()

local InputKeyMapService = require("InputKeyMapService")
local ServiceBag = require("ServiceBag")

local serviceBag = ServiceBag.new()

serviceBag:GetService(InputKeyMapService)

serviceBag:Init()
serviceBag:Start()
```

### Client

Initialize `InputKeyMapServiceClient` from the client:

```luau
--!strict

local require = require("@game/ReplicatedStorage/Packages/Nevermore/Loader").load()

local InputKeyMapServiceClient = require("InputKeyMapServiceClient")
local ServiceBag = require("ServiceBag")

local serviceBag = ServiceBag.new()

serviceBag:GetService(InputKeyMapServiceClient)

serviceBag:Init()
serviceBag:Start()
```

In a larger Nevermore game, you will normally use one shared `ServiceBag` for all services instead of creating a separate bag only for input keymaps.

## Defining an Input Provider

The following provider declares four gameplay actions:

- Jump
- Interact
- Sprint
- Reload

```luau
--!strict
-- GeneralInputKeyMapProvider.lua

local require = require("@game/ReplicatedStorage/Packages/Nevermore/Loader").load()

local InputKeyMap = require("InputKeyMap")
local InputKeyMapList = require("InputKeyMapList")
local InputKeyMapListProvider = require("InputKeyMapListProvider")
local InputModeTypes = require("InputModeTypes")
local SlottedTouchButtonUtils = require("SlottedTouchButtonUtils")

local GeneralInputKeyMapProvider = InputKeyMapListProvider.new(
	"General",
	function(self, _serviceBag)
		self:Add(InputKeyMapList.new("JUMP", {
			InputKeyMap.new(InputModeTypes.KeyboardAndMouse, {
				Enum.KeyCode.Space,
			}),

			InputKeyMap.new(InputModeTypes.Gamepads, {
				Enum.KeyCode.ButtonA,
			}),

			InputKeyMap.new(InputModeTypes.Touch, {
				SlottedTouchButtonUtils.createSlottedTouchButton("primary1"),
			}),
		}, {
			bindingName = "Jump",
			rebindable = true,
		}))

		self:Add(InputKeyMapList.new("INTERACT", {
			InputKeyMap.new(InputModeTypes.KeyboardAndMouse, {
				Enum.KeyCode.E,
			}),

			InputKeyMap.new(InputModeTypes.Gamepads, {
				Enum.KeyCode.ButtonX,
			}),

			InputKeyMap.new(InputModeTypes.Touch, {
				SlottedTouchButtonUtils.createSlottedTouchButton("primary2"),
			}),
		}, {
			bindingName = "Interact",
			rebindable = true,
		}))

		self:Add(InputKeyMapList.new("SPRINT", {
			InputKeyMap.new(InputModeTypes.KeyboardAndMouse, {
				Enum.KeyCode.LeftShift,
			}),

			InputKeyMap.new(InputModeTypes.Gamepads, {
				Enum.KeyCode.ButtonL3,
			}),

			InputKeyMap.new(InputModeTypes.Touch, {
				SlottedTouchButtonUtils.createSlottedTouchButton("secondary1"),
			}),
		}, {
			bindingName = "Sprint",
			rebindable = true,
		}))

		self:Add(InputKeyMapList.new("RELOAD", {
			InputKeyMap.new(InputModeTypes.KeyboardAndMouse, {
				Enum.KeyCode.R,
			}),

			InputKeyMap.new(InputModeTypes.Gamepads, {
				Enum.KeyCode.ButtonY,
			}),

			InputKeyMap.new(InputModeTypes.Touch, {
				SlottedTouchButtonUtils.createSlottedTouchButton("secondary2"),
			}),
		}, {
			bindingName = "Reload",
			rebindable = true,
		}))
	end
)

return GeneralInputKeyMapProvider
```

The first constructor argument is the provider name:

```luau
"General"
```

Each `InputKeyMapList` has an internal action name:

```luau
"INTERACT"
```

It also has a player-facing name:

```luau
bindingName = "Interact"
```

Keeping these separate is useful because internal names should remain stable, while visible names may be localized or changed for presentation.

## Registering and Retrieving the Provider

Providers are Nevermore services and should be retrieved through the `ServiceBag`.

```luau
local GeneralInputKeyMapProvider = require("GeneralInputKeyMapProvider")

local generalProvider =
	serviceBag:GetService(GeneralInputKeyMapProvider)
```

After the `ServiceBag` has been initialized, retrieve an action with:

```luau
local interactKeyMapList =
	generalProvider:GetInputKeyMapList("INTERACT")
```

`GetInputKeyMapList()` errors when the requested action is not defined.

Use `FindInputKeyMapList()` when the action may be absent:

```luau
local optionalMap =
	generalProvider:FindInputKeyMapList("OPTIONAL_ACTION")

if optionalMap then
	print("Optional action is available")
end
```

## Reading Bindings Directly

You can read the bindings for a specific input mode:

```luau
local keyboardInputs = interactKeyMapList:GetInputTypesList(
	InputModeTypes.KeyboardAndMouse
)

local gamepadInputs = interactKeyMapList:GetInputTypesList(
	InputModeTypes.Gamepads
)
```

For the provider above, the values would conceptually be:

```luau
keyboardInputs == {
	Enum.KeyCode.E,
}

gamepadInputs == {
	Enum.KeyCode.ButtonX,
}
```

The input list may contain more than plain `Enum.KeyCode` values. Depending on the map, it can also contain:

- `Enum.UserInputType`
- Input chords
- Slotted touch-button definitions
- Other supported input descriptors

Do not assume every entry is always a `KeyCode`.

## Observing the Active Input Binding

A keymap list contains mappings for multiple input modes, but UI generally wants to show only the binding relevant to the player's current device.

Use `InputKeyMapListUtils.observeActiveInputTypesList()`:

```luau
--!strict

local require = require("@game/ReplicatedStorage/Packages/Nevermore/Loader").load()

local InputKeyMapListUtils = require("InputKeyMapListUtils")
local Maid = require("Maid")

local maid = Maid.new()

local interactKeyMapList =
	generalProvider:GetInputKeyMapList("INTERACT")

maid:GiveTask(
	InputKeyMapListUtils
		.observeActiveInputTypesList(interactKeyMapList, serviceBag)
		:Subscribe(function(inputTypes)
			local primaryInput = inputTypes[1]

			if primaryInput then
				print("Current Interact input:", primaryInput)
			else
				print("Interact has no active binding")
			end
		end)
)
```

When the player switches devices, the observable can emit a new list:

```text
Keyboard used
    → { Enum.KeyCode.E }

Gamepad used
    → { Enum.KeyCode.ButtonX }

Touch used
    → { SlottedTouchButton("primary2") }
```

This makes the observable appropriate for:

- Input hint widgets
- Tutorial prompts
- Interaction indicators
- Ability HUDs
- Control settings menus

## Binding an Action to Gameplay

`InputKeyMapUtils` does not invoke the action itself. One way to consume the keymap is to pass its Roblox-compatible inputs to `ContextActionService`.

The following controller binds Sprint and automatically rebinds the action whenever its input list changes.

```luau
--!strict
-- SprintController.lua

local require = require("@game/ReplicatedStorage/Packages/Nevermore/Loader").load()

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local BaseObject = require("BaseObject")
local GeneralInputKeyMapProvider = require("GeneralInputKeyMapProvider")
local Rx = require("Rx")

local SprintController = setmetatable({}, BaseObject)
SprintController.ClassName = "SprintController"
SprintController.__index = SprintController

local ACTION_NAME = "Sprint"
local NORMAL_SPEED = 16
local SPRINT_SPEED = 24

function SprintController.new(serviceBag)
	local self = setmetatable(
		BaseObject.new() :: any,
		SprintController
	)

	self._serviceBag = serviceBag
	self._generalInputProvider =
		serviceBag:GetService(GeneralInputKeyMapProvider)

	self._sprintKeyMapList =
		self._generalInputProvider:GetInputKeyMapList("SPRINT")

	self._humanoid = nil
	self._isSprinting = false

	self:_observeCharacter()
	self:_bindInput()

	return self
end

function SprintController:_observeCharacter()
	local player = Players.LocalPlayer

	local function handleCharacter(character: Model)
		self:_setSprinting(false)

		local humanoid =
			character:WaitForChild("Humanoid") :: Humanoid

		self._humanoid = humanoid
		humanoid.WalkSpeed = NORMAL_SPEED

		self._maid._currentCharacter = function()
			if self._humanoid == humanoid then
				self._humanoid = nil
			end
		end
	end

	self._maid:GiveTask(player.CharacterAdded:Connect(handleCharacter))

	if player.Character then
		handleCharacter(player.Character)
	end
end

function SprintController:_bindInput()
	self._maid:GiveTask(
		Rx.combineLatest({
			inputEnums =
				self._sprintKeyMapList:ObserveInputEnumsList(),

			createTouchButton =
				self._sprintKeyMapList
					:ObserveIsRobloxTouchButton(),
		}):Subscribe(function(state)
			ContextActionService:UnbindAction(ACTION_NAME)

			self:_setSprinting(false)

			if #state.inputEnums == 0 then
				return
			end

			ContextActionService:BindActionAtPriority(
				ACTION_NAME,
				function(
					_actionName: string,
					inputState: Enum.UserInputState,
					_inputObject: InputObject
				)
					return self:_handleSprintInput(inputState)
				end,
				state.createTouchButton,
				Enum.ContextActionPriority.Default.Value,
				table.unpack(state.inputEnums)
			)
		end)
	)

	self._maid:GiveTask(function()
		ContextActionService:UnbindAction(ACTION_NAME)
		self:_setSprinting(false)
	end)
end

function SprintController:_handleSprintInput(
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		self:_setSprinting(true)
	elseif inputState == Enum.UserInputState.End
		or inputState == Enum.UserInputState.Cancel
	then
		self:_setSprinting(false)
	end

	return Enum.ContextActionResult.Sink
end

function SprintController:_setSprinting(isSprinting: boolean)
	self._isSprinting = isSprinting

	if self._humanoid then
		self._humanoid.WalkSpeed = if isSprinting
			then SPRINT_SPEED
			else NORMAL_SPEED
	end
end

return SprintController
```

When one device binding changes, `ObserveInputEnumsList()` emits the complete current input list.

For example, suppose Sprint originally uses:

```text
Keyboard: LeftShift
Gamepad:  ButtonL3
```

If the keyboard binding changes to `LeftControl`, the new complete list becomes:

```text
Keyboard: LeftControl
Gamepad:  ButtonL3
```

The controller unbinds the old action and binds the complete updated list. The unchanged gamepad binding is therefore restored as part of the new action binding.

## Showing Input Icons with InputImageLibrary

`InputImageLibrary` converts supported input values into sprites for an `ImageLabel` or `ImageButton`.

The normal UI flow is:

```text
InputKeyMapList
        │
        ▼
Observe active input types
        │
        ▼
Choose the primary input
        │
        ▼
InputImageLibrary:StyleImage()
        │
        ▼
Keyboard, mouse, or gamepad icon
```

### Basic Icon Example

```luau
local InputImageLibrary = require("InputImageLibrary")

local sprite = InputImageLibrary:StyleImage(
	imageLabel,
	Enum.KeyCode.ButtonX
)
```

`StyleImage()` configures the image properties of the supplied `ImageLabel` or `ImageButton`.

It returns the styled GUI when an appropriate sprite is found, or `nil` when the library has no matching sprite.

You can also specify a preferred style:

```luau
InputImageLibrary:StyleImage(
	imageLabel,
	Enum.KeyCode.E,
	"Dark"
)
```

Or a preferred platform:

```luau
InputImageLibrary:StyleImage(
	imageLabel,
	Enum.KeyCode.ButtonX,
	"Dark",
	"PlayStation"
)
```

When no preferred gamepad platform is supplied, the library attempts to select the current platform automatically.

## Complete Reactive Input-Hint Component

This component displays:

- The icon for the currently active binding
- The action's player-facing name
- A fallback text value when no sprite exists
- Automatic updates when the player changes input device
- Automatic updates when the action is rebound

Expected UI hierarchy:

```text
InputHint
├── KeyIcon: ImageLabel
├── KeyText: TextLabel
└── ActionText: TextLabel
```

Example result:

```text
Keyboard:
[E] Interact

Gamepad:
[X icon] Interact
```

```luau
--!strict
-- InputHint.lua

local require = require("@game/ReplicatedStorage/Packages/Nevermore/Loader").load()

local BaseObject = require("BaseObject")
local InputImageLibrary = require("InputImageLibrary")
local InputKeyMapListUtils = require("InputKeyMapListUtils")

local InputHint = setmetatable({}, BaseObject)
InputHint.ClassName = "InputHint"
InputHint.__index = InputHint

export type InputHint = typeof(setmetatable(
	{} :: {
		_gui: Frame,
		_keyIcon: ImageLabel,
		_keyText: TextLabel,
		_actionText: TextLabel,
	},
	{} :: typeof({ __index = InputHint })
))

function InputHint.new(
	gui: Frame,
	inputKeyMapList,
	serviceBag
): InputHint
	assert(typeof(gui) == "Instance" and gui:IsA("Frame"), "Bad gui")
	assert(inputKeyMapList, "Bad inputKeyMapList")
	assert(serviceBag, "Bad serviceBag")

	local self: InputHint =
		setmetatable(BaseObject.new(gui) :: any, InputHint)

	self._gui = gui
	self._keyIcon = gui:WaitForChild("KeyIcon") :: ImageLabel
	self._keyText = gui:WaitForChild("KeyText") :: TextLabel
	self._actionText =
		gui:WaitForChild("ActionText") :: TextLabel

	self._actionText.Text =
		inputKeyMapList:GetBindingName()

	self._maid:GiveTask(
		InputKeyMapListUtils
			.observeActiveInputTypesList(
				inputKeyMapList,
				serviceBag
			)
			:Subscribe(function(inputTypes)
				self:_renderInput(inputTypes[1])
			end)
	)

	return self
end

function InputHint:_renderInput(inputType)
	self:_clearIcon()

	if inputType == nil then
		self._keyIcon.Visible = false
		self._keyText.Visible = false
		return
	end

	local styledImage = InputImageLibrary:StyleImage(
		self._keyIcon,
		inputType,
		"Dark"
	)

	if styledImage then
		self._keyIcon.Visible = true
		self._keyText.Visible = false
	else
		self._keyIcon.Visible = false
		self._keyText.Visible = true
		self._keyText.Text =
			self:_getFallbackInputText(inputType)
	end
end

function InputHint:_clearIcon()
	self._keyIcon.Image = ""
	self._keyIcon.ImageRectOffset = Vector2.zero
	self._keyIcon.ImageRectSize = Vector2.zero
end

function InputHint:_getFallbackInputText(inputType): string
	if typeof(inputType) == "EnumItem" then
		return self:_formatEnumName(inputType.Name)
	end

	return tostring(inputType)
end

function InputHint:_formatEnumName(name: string): string
	local formatted = name
		:gsub("Button", "")
		:gsub("LeftShift", "Left Shift")
		:gsub("RightShift", "Right Shift")
		:gsub("LeftControl", "Left Ctrl")
		:gsub("RightControl", "Right Ctrl")
		:gsub("MouseButton1", "LMB")
		:gsub("MouseButton2", "RMB")

	return formatted
end

return InputHint
```

Use it from another client controller:

```luau
local GeneralInputKeyMapProvider =
	require("GeneralInputKeyMapProvider")

local InputHint = require("InputHint")

local generalProvider =
	serviceBag:GetService(GeneralInputKeyMapProvider)

local interactKeyMapList =
	generalProvider:GetInputKeyMapList("INTERACT")

local inputHint = InputHint.new(
	playerGui.Hud.InteractHint,
	interactKeyMapList,
	serviceBag
)

maid:GiveTask(inputHint)
```

The component will update when:

1. The player switches from keyboard to gamepad.
2. The player switches from gamepad back to keyboard.
3. The current input mode's key is rebound.
4. The binding is removed.
5. A supported input has an image sprite.
6. An unsupported input needs fallback text.

## Getting a Sprite Without Styling Immediately

Use `GetSprite()` when you need the sprite object itself:

```luau
local sprite = InputImageLibrary:GetSprite(
	Enum.KeyCode.ButtonA,
	"Dark",
	nil
)

if sprite then
	sprite:Style(imageLabel)
end
```

This is useful when:

- You want to inspect whether a sprite exists
- You want to delay styling
- You need to reuse the sprite
- You are building your own UI abstraction

## Creating a Scaled Input Image

`InputImageLibrary` can also create an image instance with an aspect-ratio constraint:

```luau
local image = InputImageLibrary:GetScaledImageLabel(
	Enum.KeyCode.ButtonA,
	"Dark"
)

if image then
	image.Parent = inputContainer
end
```

This is convenient when the UI does not already contain an `ImageLabel`.

## Preloading Input Icons

The library exposes the sprite-sheet asset IDs it uses:

```luau
local ContentProvider = game:GetService("ContentProvider")

local assetIds =
	InputImageLibrary:GetPreloadAssetIds()

ContentProvider:PreloadAsync(assetIds)
```

For a Nevermore-based preload flow, pass these IDs into your existing content-preloading system.

Preloading avoids the icon appearing late the first time an input hint becomes visible.

## Choosing Between Icons and Text

Prefer icons for:

- Gamepad buttons
- Mouse buttons
- Compact HUD prompts
- Ability bars
- Tutorial callouts

Text may be clearer for:

- Keyboard keys
- Settings lists
- Accessibility modes
- Unsupported custom inputs
- Chords that are difficult to represent with one icon

A polished hint can support both:

```text
[icon] Interact
```

with a text fallback:

```text
[E] Interact
```

## Multiple Bindings

An action may contain multiple active inputs:

```luau
InputKeyMap.new(InputModeTypes.KeyboardAndMouse, {
	Enum.KeyCode.E,
	Enum.KeyCode.F,
})
```

`observeActiveInputTypesList()` returns the entire active list.

A simple HUD hint can show only the first entry:

```luau
local primaryInput = inputTypes[1]
```

A controls menu may display every entry:

```luau
for _, inputType in inputTypes do
	createInputIcon(inputType)
end
```

Conceptually:

```text
[E] / [F] Interact
```

## Input Chords

Some actions may require a combination instead of one key:

```text
LeftControl + R
LeftShift + E
ButtonL2 + ButtonX
```

A chord is not necessarily representable by one `ImageLabel`.

For chord UI, render each component separately:

```text
[Ctrl] + [R]
```

Your UI layer should therefore distinguish between:

- A single `EnumItem`
- An input chord
- A slotted touch button
- Another custom input descriptor

Do not rely exclusively on `tostring()` for production UI.

## ProximityPrompt Integration

`ProximityPromptInputUtils` can copy the first keyboard and gamepad `KeyCode` from an `InputKeyMapList` into a Roblox `ProximityPrompt`.

```luau
local ProximityPromptInputUtils =
	require("ProximityPromptInputUtils")

local interactKeyMapList =
	generalProvider:GetInputKeyMapList("INTERACT")

ProximityPromptInputUtils.configurePromptFromInputKeyMap(
	proximityPrompt,
	interactKeyMapList
)
```

For the provider above, this configures:

```luau
proximityPrompt.KeyboardKeyCode = Enum.KeyCode.E
proximityPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
```

The utility only assigns supported `Enum.KeyCode` values.

The touch map is not copied into a `ProximityPrompt` key-code property because Roblox prompts handle touch interaction through their own mobile presentation.

### Creating a Keymap from an Existing Prompt

You can also construct a non-rebindable keymap from a prompt:

```luau
local inputKeyMapList =
	ProximityPromptInputUtils.newInputKeyMapFromPrompt(
		proximityPrompt
	)
```

The resulting list uses:

- `prompt.KeyboardKeyCode`
- `prompt.GamepadKeyCode`
- A default primary touch slot
- `prompt.ActionText` as the binding name
- `rebindable = false`

## Keeping a ProximityPrompt Updated After Rebinding

A one-time call to `configurePromptFromInputKeyMap()` only copies the bindings that exist at that moment.

To react to future rebindings, observe the keymap and configure the prompt again:

```luau
maid:GiveTask(
	interactKeyMapList
		:ObserveInputEnumsList()
		:Subscribe(function()
			ProximityPromptInputUtils
				.configurePromptFromInputKeyMap(
					proximityPrompt,
					interactKeyMapList
				)
		end)
)
```

The observable value itself is not required in this callback because the utility reads the current keyboard and gamepad maps directly.

## Example: Complete Interactable Prompt Controller

This example combines:

- `InputKeyMapListProvider`
- `ProximityPromptInputUtils`
- `InputKeyMapListUtils`
- `InputImageLibrary`
- Reactive cleanup with `Maid`

```luau
--!strict
-- InteractPromptController.lua

local require = require("@game/ReplicatedStorage/Packages/Nevermore/Loader").load()

local BaseObject = require("BaseObject")
local GeneralInputKeyMapProvider =
	require("GeneralInputKeyMapProvider")
local InputImageLibrary = require("InputImageLibrary")
local InputKeyMapListUtils =
	require("InputKeyMapListUtils")
local ProximityPromptInputUtils =
	require("ProximityPromptInputUtils")

local InteractPromptController =
	setmetatable({}, BaseObject)

InteractPromptController.ClassName =
	"InteractPromptController"

InteractPromptController.__index =
	InteractPromptController

function InteractPromptController.new(
	proximityPrompt: ProximityPrompt,
	hintGui: Frame,
	serviceBag
)
	assert(
		typeof(proximityPrompt) == "Instance"
			and proximityPrompt:IsA("ProximityPrompt"),
		"Bad proximityPrompt"
	)

	assert(
		typeof(hintGui) == "Instance"
			and hintGui:IsA("Frame"),
		"Bad hintGui"
	)

	local self = setmetatable(
		BaseObject.new(proximityPrompt) :: any,
		InteractPromptController
	)

	self._prompt = proximityPrompt
	self._hintGui = hintGui
	self._icon =
		hintGui:WaitForChild("KeyIcon") :: ImageLabel
	self._keyText =
		hintGui:WaitForChild("KeyText") :: TextLabel
	self._actionText =
		hintGui:WaitForChild("ActionText") :: TextLabel

	local provider = serviceBag:GetService(
		GeneralInputKeyMapProvider
	)

	self._interactMap =
		provider:GetInputKeyMapList("INTERACT")

	self._actionText.Text =
		self._interactMap:GetBindingName()

	self:_configureRobloxPrompt()
	self:_observePromptBindings(serviceBag)

	return self
end

function InteractPromptController:_configureRobloxPrompt()
	ProximityPromptInputUtils.configurePromptFromInputKeyMap(
		self._prompt,
		self._interactMap
	)
end

function InteractPromptController:_observePromptBindings(
	serviceBag
)
	self._maid:GiveTask(
		self._interactMap
			:ObserveInputEnumsList()
			:Subscribe(function()
				self:_configureRobloxPrompt()
			end)
	)

	self._maid:GiveTask(
		InputKeyMapListUtils
			.observeActiveInputTypesList(
				self._interactMap,
				serviceBag
			)
			:Subscribe(function(inputTypes)
				self:_renderHint(inputTypes[1])
			end)
	)
end

function InteractPromptController:_renderHint(inputType)
	self._icon.Image = ""
	self._icon.ImageRectOffset = Vector2.zero
	self._icon.ImageRectSize = Vector2.zero

	if inputType == nil then
		self._icon.Visible = false
		self._keyText.Visible = false
		return
	end

	local image = InputImageLibrary:StyleImage(
		self._icon,
		inputType,
		"Dark"
	)

	if image then
		self._icon.Visible = true
		self._keyText.Visible = false
	else
		self._icon.Visible = false
		self._keyText.Visible = true

		if typeof(inputType) == "EnumItem" then
			self._keyText.Text = inputType.Name
		else
			self._keyText.Text = tostring(inputType)
		end
	end
end

return InteractPromptController
```

This lets the built-in Roblox prompt and a custom HUD hint share the same action definition.

```text
InputKeyMapList: INTERACT
          │
          ├── ProximityPrompt key codes
          └── Custom input-hint icon
```

## Rebinding

A controls menu can replace the input list for one input mode without modifying the other modes.

For example, change Interact from `E` to `F`:

```luau
interactKeyMapList:SetInputTypesList(
	InputModeTypes.KeyboardAndMouse,
	{
		Enum.KeyCode.F,
	}
)
```

The gamepad binding remains unchanged:

```text
Before:
├── Keyboard: E
└── Gamepad: ButtonX

After:
├── Keyboard: F
└── Gamepad: ButtonX
```

Observers of the keymap receive the updated binding state.

This allows the following systems to update without being directly coupled to the settings menu:

- Gameplay action bindings
- Input hint icons
- Proximity prompts
- Controls menus
- Tutorial text

## Restoring Defaults

Rebindable lists can be restored to their declared default mappings:

```luau
interactKeyMapList:RestoreDefault()
```

A controls menu can expose this as:

```text
Reset Interact
```

or restore all actions from a provider by iterating over its keymap lists.

## Suggested Project Structure

```text
ReplicatedStorage
└── Shared
    └── Input
        ├── GeneralInputKeyMapProvider.lua
        ├── WeaponInputKeyMapProvider.lua
        └── VehicleInputKeyMapProvider.lua

StarterPlayer
└── StarterPlayerScripts
    └── Controllers
        ├── SprintController.lua
        ├── InputHintController.lua
        └── ControlsSettingsController.lua

StarterGui
└── Hud
    ├── InteractHint
    ├── AbilityHints
    └── ControlsMenu
```

Keep action definitions in providers and consume them from controllers.

Avoid constructing a new `InputKeyMapList` independently in every gameplay system, since those copies would not share rebindings.

## Recommended Responsibilities

### Input providers

Responsible for:

- Declaring action names
- Declaring default bindings
- Declaring whether actions are rebindable
- Grouping related actions

### Gameplay controllers

Responsible for:

- Binding inputs
- Responding to input states
- Activating gameplay behavior
- Cleaning up bindings

### UI controllers

Responsible for:

- Observing the active input mode
- Showing icons or fallback text
- Rendering multiple bindings
- Reacting to rebinding

### Settings systems

Responsible for:

- Capturing a replacement input
- Validating allowed inputs
- Detecting conflicts
- Calling keymap mutation methods
- Saving player preferences
- Restoring defaults

## Common Mistakes

### Expecting InputKeyMapUtils to fire the action

This package stores binding data:

```text
SPRINT → LeftShift / ButtonL3
```

It does not automatically call:

```luau
character:SetSprinting(true)
```

You must connect the data to an input-dispatch system.

---

### Hardcoding UI separately from gameplay

Avoid:

```luau
label.Text = "Press E"
```

when gameplay reads its binding from an `InputKeyMapList`.

After rebinding, gameplay and UI would disagree.

Instead, derive both from the same keymap list.

---

### Showing every platform at once

Avoid showing:

```text
E / ButtonX / Touch primary2
```

in a normal HUD hint.

Observe the player's active input mode and display only the relevant binding.

A controls settings page may intentionally show every platform.

---

### Assuming every input is an EnumItem

Touch slots and input chords may not be `Enum.KeyCode` values.

Check the value before reading `.Name`:

```luau
if typeof(inputType) == "EnumItem" then
	print(inputType.Name)
end
```

---

### Assuming every input has an image

`InputImageLibrary:StyleImage()` may return `nil`.

Always provide fallback text or hide the hint gracefully.

---

### Configuring a prompt only once

If an action is rebindable, a one-time prompt configuration becomes stale.

Observe the keymap and reconfigure the prompt when it changes.

---

### Defining duplicate providers

Retrieve providers through the `ServiceBag`:

```luau
serviceBag:GetService(GeneralInputKeyMapProvider)
```

Do not manually invoke the provider constructor or clone the keymap declarations.

## When to Use InputKeyMapUtils

Use it when your game needs:

- Keyboard, gamepad, and touch support
- Rebindable controls
- Device-aware input hints
- Centralized action definitions
- Controls settings
- Shared bindings across multiple systems
- ProximityPrompt integration
- Reactive UI updates

For a tiny, non-rebindable prototype, direct input handling may be simpler:

```luau
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.E then
		interact()
	end
end)
```

For a larger cross-platform game, `InputKeyMapUtils` keeps the action separate from the physical control:

```text
Gameplay concept
      │
      ▼
   INTERACT
      │
      ├── Keyboard: E
      ├── Gamepad: ButtonX
      └── Touch: primary2
```

Gameplay understands the action `"INTERACT"`.

The keymap system decides which physical input currently represents it.

The UI uses the same mapping to show the correct input icon.

## Summary

`InputKeyMapUtils` is the binding-data layer of an input architecture.

It provides:

```text
Action definitions
        +
Cross-platform mappings
        +
Rebinding observation
        +
Provider registration
```

Pair it with:

```text
ContextActionService
    → Gameplay input dispatch

InputImageLibrary
    → Keyboard, mouse, and gamepad icons

ProximityPromptInputUtils
    → Roblox prompt key configuration

A settings system
    → Capturing and saving custom bindings
```

Together, these systems provide one source of truth for gameplay controls and their UI presentation.
