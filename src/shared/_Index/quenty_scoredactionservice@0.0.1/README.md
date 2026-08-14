# ScoredActionService

ScoredActionService coordinates several actions that may respond to the same input. Each action receives a score, and the highest-scoring enabled action becomes preferred for its active input type. This is useful when a key has different meanings depending on context, such as `E` opening a door nearby while also interacting with a shop farther away.

The service evaluates registered actions every frame. Higher scores win. If scores are equal, the action created first wins. A score of `-math.huge` means that an action can never become preferred.

## Installation

The package is already part of this Nevermore source tree. Register the service with the same `ServiceBag` used by your input services:

```luau
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
local ScoredActionServiceClient = require("@game/ReplicatedStorage/Packages/ScoredActionServiceClient")

local serviceBag = ServiceBag.new()
serviceBag:GetService(ScoredActionServiceClient)
serviceBag:Init()
serviceBag:Start()
```

`ScoredActionServiceClient` requires `InputModeServiceClient` and `InputKeyMapServiceClient`. The server-side `ScoredActionService` similarly wires `InputKeyMapService` and does not perform client-side scoring.

## Basic example

Create one scored action for an existing `InputKeyMapList`, then update its score as the game state changes:

```luau
local InputKeyMapList = require("@game/ReplicatedStorage/Packages/InputKeyMapList")
local ScoredActionServiceClient = require("@game/ReplicatedStorage/Packages/ScoredActionServiceClient")

local inputKeyMapList = InputKeyMapList.fromInputKeys({ Enum.KeyCode.E }, {
	bindingName = "Open nearby door",
	rebindable = false,
})

local scoredActionService = serviceBag:GetService(ScoredActionServiceClient)
local scoredAction = scoredActionService:GetScoredAction(inputKeyMapList)

scoredAction:SetScore(100)

maid:GiveTask(scoredAction:ObservePreferred():Subscribe(function(isPreferred)
	if isPreferred then
		print("The door owns the E key")
	end
end))

maid:GiveTask(scoredAction)
```

When the action is destroyed, it is removed from the picker automatically. Always give the returned action to a `Maid` or another owner with a matching lifetime.

## Context-sensitive scores

Keep the same `InputKeyMapList` and change the score whenever the context changes:

```luau
local scoredAction = scoredActionService:GetScoredAction(inputKeyMapList)

local function updateScore(distance: number, canOpen: boolean)
	if not canOpen then
		scoredAction:SetScore(-math.huge)
		return
	end

	scoredAction:SetScore(1000 - distance)
end
```

An action can also be disabled without destroying it:

```luau
scoredAction:SetIsEnabled(false)
print(scoredAction:IsEnabled()) -- false

scoredAction:SetIsEnabled(true)
```

`SetIsEnabled` accepts either a boolean or an `Observable<boolean>`.

## Multiple actions on the same key

Create separate input lists with the same key. ScoredActionService places them in the same picker and prefers the enabled action with the highest score:

```luau
local InputKeyMapList = require("@game/ReplicatedStorage/Packages/InputKeyMapList")
local ScoredActionServiceClient = require("@game/ReplicatedStorage/Packages/ScoredActionServiceClient")

local openDoorKeys = InputKeyMapList.fromInputKeys({ Enum.KeyCode.E }, {
	bindingName = "Open door",
	rebindable = false,
})
local talkToNpcKeys = InputKeyMapList.fromInputKeys({ Enum.KeyCode.E }, {
	bindingName = "Talk to NPC",
	rebindable = false,
})

local scoredActionService = serviceBag:GetService(ScoredActionServiceClient)
local openDoor = scoredActionService:GetScoredAction(openDoorKeys)
local talkToNpc = scoredActionService:GetScoredAction(talkToNpcKeys)

openDoor:SetScore(50)
talkToNpc:SetScore(100)

-- `talkToNpc` is preferred because 100 is higher than 50.
maid:GiveTask(talkToNpc:ObservePreferred():Subscribe(function(isPreferred)
	if isPreferred then
		print("E now talks to the NPC")
	end
end))
```

Scores can change as the player moves between contexts:

```luau
local function updateInteractionScores(doorDistance: number?, npcDistance: number?)
	openDoor:SetScore(doorDistance and 1000 - doorDistance or -math.huge)
	talkToNpc:SetScore(npcDistance and 1000 - npcDistance or -math.huge)
end

updateInteractionScores(8, 30) -- The door wins.
updateInteractionScores(nil, 4) -- The NPC wins.
```

If both actions have the same score, the action created first wins. An action with `-math.huge` is never selected, which is useful when an interaction is unavailable.

## Observing a stream of input lists

`ObserveNewFromInputKeyMapList` converts an observable stream of input lists into a stream of owned `ScoredAction` objects. The emitted action is destroyed when the next input list arrives or the subscription ends.

```luau
local ValueObject = require("@game/ReplicatedStorage/Packages/ValueObject")

local scoreValue = ValueObject.new(10)

maid:GiveTask(
	inputKeyMapLists:Pipe({
		scoredActionService:ObserveNewFromInputKeyMapList(scoreValue),
	}):Subscribe(function(scoredAction, inputKeyMapList)
		print("Scoring", inputKeyMapList:GetListName(), scoredAction:GetScore())
	end)
)
```

Keep the source observable alive for as long as the scored action should exist. A source that completes immediately can hand back an already-destroyed action.

## `ScoredAction` methods

| Method | Description |
| --- | --- |
| `SetScore(number)` | Sets the action priority. Higher values win. |
| `GetScore()` | Returns the current score. |
| `SetIsEnabled(boolean \| Observable<boolean>)` | Enables, disables, or reactively controls the action. |
| `IsEnabled()` | Returns whether the action may be selected. |
| `ObserveIsEnabled()` | Observes enabled-state changes. |
| `IsPreferred()` | Returns whether this action currently owns its input slot. |
| `ObservePreferred()` | Observes preference changes. |
| `PushPreferred()` | Temporarily forces preference; the returned cleanup function releases it. |

## `ScoredActionServiceClient` methods

| Method | Description |
| --- | --- |
| `GetScoredAction(inputKeyMapList)` | Creates an action tied to an `InputKeyMapList`. |
| `ObserveNewFromInputKeyMapList(scoreValue)` | Returns an Rx transformer that creates actions from input-list emissions. |

## Input behavior

Keyboard, mouse, and gamepad input types compete within their picker, so only the preferred action receives that slot. Touch-button actions are handled separately: every enabled touch action with a finite score may remain preferred because touch buttons do not share one physical input slot.
