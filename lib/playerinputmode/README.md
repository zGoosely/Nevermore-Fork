# PlayerInputMode

`PlayerInputModeServiceClient` converts local InputMode activity into one of
three public control families:

- `PlayerInputModeTypes.GAMEPAD` (`"gamepad"`)
- `PlayerInputModeTypes.KEYBOARD` (`"keyboard"`)
- `PlayerInputModeTypes.TOUCH` (`"touch"`)

It reports changes to `PlayerInputModeService` with a one-byte ByteNet packet.
The server validates and rate-limits the report, then writes the result to the
player's `PlayerInputMode` attribute. Roblox attribute replication makes the
validated value available to the server and every client.

## Setup

Register the server service in the server ServiceBag:

```luau
const PlayerInputModeService = require("PlayerInputModeService")
const ServiceBag = require("ServiceBag")

local serviceBag = ServiceBag.new()
local playerInputModes = serviceBag:GetService(PlayerInputModeService)

serviceBag:Init()
serviceBag:Start()
```

Register the client service in the client ServiceBag:

```luau
const PlayerInputModeServiceClient = require("PlayerInputModeServiceClient")
const ServiceBag = require("ServiceBag")

local serviceBag = ServiceBag.new()
local playerInputModes = serviceBag:GetService(PlayerInputModeServiceClient)

serviceBag:Init()
serviceBag:Start()
```

The client service automatically initializes its `InputModeServiceClient`
dependency. Do not also create a separate InputMode service instance.

## Common use cases

PlayerInputMode is intended for cases where somebody besides the local player
needs the broad input family:

- Display a keyboard, touch, or controller badge in a lobby roster.
- Show a teammate's likely communication or control style in an overhead UI.
- Present cross-input party or matchmaking information.
- Record approximate control-family adoption in server analytics.
- Pick an initial tutorial presentation before the player's local UI takes over.
- Let spectators choose suitable control hints for the player they are watching.

A client can display a live input label for another player:

```luau
const PlayerInputModeTypes = require("PlayerInputModeTypes")

local MODE_LABELS = {
	[PlayerInputModeTypes.GAMEPAD] = "Controller",
	[PlayerInputModeTypes.KEYBOARD] = "Keyboard & Mouse",
	[PlayerInputModeTypes.TOUCH] = "Touch",
}

maid:Add(playerInputModes:ObservePlayerInputType(otherPlayer):Subscribe(function(inputMode)
	rosterInputLabel.Text = if inputMode then MODE_LABELS[inputMode] or "Unknown" else "Unknown"
end))
```

For local button prompts, touch controls, and detailed modes such as mouse,
thumbstick, D-pad, or WASD, use InputMode directly. Replicating those decisions
through PlayerInputMode adds no benefit when only the local UI consumes them.

## Reading a player's mode

The same synchronous and observable methods exist on the server and client:

```luau
const PlayerInputModeTypes = require("PlayerInputModeTypes")

local currentMode = playerInputModes:GetPlayerInputModeType(player)

if currentMode == PlayerInputModeTypes.TOUCH then
	print("Use larger interaction prompts")
end

maid:Add(playerInputModes:ObservePlayerInputType(player):Subscribe(function(inputMode)
	print(player.Name, "is now using", inputMode)
end))
```

The value is `nil` until the player's client makes its first valid report. On the
server, wait for that first report when necessary:

```luau
playerInputModes:GetPlayerInputModeAsync(player):Then(function(inputMode)
	print("Initial input mode", inputMode)
end)
```

`GetPlayerInputModeAsync()` optionally accepts a `CancelToken` as its second
argument.

## Local selector

After the client service has started, its underlying selector is available for
local UI that needs the full InputModeType object:

```luau
local selector = playerInputModes:GetSelector()

maid:Add(selector:ObserveActiveInputType():Subscribe(function(inputModeType)
	print(inputModeType and inputModeType.Name)
end))
```

For more specialized modes such as mouse-only, WASD, D-pad, or custom key groups,
use `InputModeServiceClient` directly instead of expanding the three replicated
values.

## Networking and trust boundary

The client sends only a `uint8` code through `PlayerInputModeNetwork`:

```text
0 = gamepad
1 = keyboard
2 = touch
```

The server rejects unknown codes, ignores duplicate values, and limits accepted
changes per player. A client can still lie about its own input family, so use this
information for UI, control hints, matchmaking presentation, or accessibility—not
as proof of device identity or for security decisions.
