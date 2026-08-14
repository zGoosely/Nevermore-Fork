# PlayerInputService

`PlayerInputService` turns local keymaps into named gameplay actions while keeping raw player input off the network.
It composes:

- `InputKeyMap` and `InputKeyMapList` for reactive cross-platform bindings;
- `InputMode` for local active-mode selection; and
- `PlayerInputMode` for coarse client and validated server-side mode filtering.

The client observes physical input. The server receives only action IDs that explicitly opt into replication. Server AI
may also trigger those registered actions for Humanoid NPC Models without simulating keys or sending network traffic.

## Choose the right action shape

| Use case | `Network` | States the server receives | Typical examples |
| --- | --- | --- | --- |
| Local-only | Omit it | None | Open settings, toggle map, UI shortcuts |
| One-shot request | Include it | `"Begin"` | Interact, reload, use item, confirm |
| Held request | Include it | `"Begin"`, `"End"`, or `"Cancel"` | Sprint, block, aim, charge, channel |

The client always emits its complete local lifecycle. The `Network.States` list only controls which states may cross the
client-to-server boundary.

## Define an action provider

Create a shared provider module and register actions with normal `InputKeyMapList` instances:

```luau
--!strict
const InputKeyMap = require("@game/ReplicatedStorage/Packages/InputKeyMap")
const InputKeyMapList = require("@game/ReplicatedStorage/Packages/InputKeyMapList")
const InputModeTypes = require("@game/ReplicatedStorage/Packages/InputModeTypes")
const PlayerInputActionProvider = require("@game/ReplicatedStorage/Packages/PlayerInputActionProvider")
const SlottedTouchButtonUtils = require("@game/ReplicatedStorage/Packages/SlottedTouchButtonUtils")

return PlayerInputActionProvider.new("General", function(provider)
	provider:AddContext("Gameplay", 10)
	provider:AddContext("Menu", 20)

	provider:AddAction({
		Id = 1,
		Name = "INTERACT",
		InputKeyMapList = InputKeyMapList.new("INTERACT", {
			InputKeyMap.new(InputModeTypes.KeyboardAndMouse, { Enum.KeyCode.E }),
			InputKeyMap.new(InputModeTypes.Gamepads, { Enum.KeyCode.ButtonX }),
			InputKeyMap.new(InputModeTypes.Touch, {
				SlottedTouchButtonUtils.createSlottedTouchButton("primary1"),
			}),
		}, {
			bindingName = "Interact",
			rebindable = true,
		}),
		AllowedContexts = { "Gameplay" },
		ConsumeInput = false,
		Network = {
			States = { "Begin" },
			Capacity = 4,
			RefillRate = 2,
		},
	})
end)
```

Action IDs must be unique across every provider and fit in a `uint16`. Actions without `Network` are client-only.
Replicated actions must explicitly specify their accepted states and token-bucket limit.

NPCs use the same network-enabled action catalog because `Network` also defines
the server-accepted states and per-action rate limit. NPCs cannot trigger
client-only actions.

The broad server mode allowlist is inferred from `KeyboardAndMouse`, `Gamepads`, and `Touch` keymaps. Set
`AllowedPlayerInputModes` explicitly when an action uses custom modes.

### Local-only action

Omit `Network` when the server has no reason to know about an action:

```luau
provider:AddAction({
	Id = 2,
	Name = "OPEN_MAP",
	InputKeyMapList = InputKeyMapList.new("OPEN_MAP", {
		InputKeyMap.new(InputModeTypes.KeyboardAndMouse, { Enum.KeyCode.M }),
		InputKeyMap.new(InputModeTypes.Gamepads, { Enum.KeyCode.ButtonSelect }),
	}, {
		bindingName = "Open map",
		rebindable = true,
	}),
	AllowedContexts = { "Gameplay" },
})
```

This action can still use contexts, restrictions, active input-mode selection, rebinding, observations, and forced
release on the client. It never creates gameplay input traffic.

### Held action

A held action must explicitly allow both states:

```luau
provider:AddAction({
	Id = 3,
	Name = "CHARGE",
	InputKeyMapList = InputKeyMapList.new("CHARGE", {
		InputKeyMap.new(InputModeTypes.KeyboardAndMouse, { Enum.UserInputType.MouseButton1 }),
		InputKeyMap.new(InputModeTypes.Gamepads, { Enum.KeyCode.ButtonR2 }),
		InputKeyMap.new(InputModeTypes.Touch, {
			SlottedTouchButtonUtils.createSlottedTouchButton("primary2"),
		}),
	}, {
		bindingName = "Charge",
		rebindable = true,
	}),
	AllowedContexts = { "Gameplay" },
	ConsumeInput = true,
	Network = {
		States = { "Begin", "End" },
		Capacity = 3,
		RefillRate = 1,
	},
})
```

### Action options

| Option | Meaning |
| --- | --- |
| `Id` | Stable global `uint16` ID. It must match on the server and client. |
| `Name` | Provider-local action name used by `GetAction`. |
| `InputKeyMapList` | The existing keymap list that owns defaults and current bindings. |
| `AllowedContexts` | Context names in which the action may begin. Defaults to `{ "Default" }`. |
| `AllowedPlayerInputModes` | Optional explicit allowlist from `PlayerInputModeTypes`. |
| `ConsumeInput` | Returns `Sink` from `ContextActionService` after this action accepts the input. |
| `ContextActionPriority` | Binding priority used when actions share a key. |
| `AllowWhenTextBoxFocused` | Allows the action to begin while a Roblox text box has focus. |
| `Network` | Opts into replication and defines accepted states and per-action token limits. |
| `CooldownType` | Optional move-specific `CooldownTypes.Default` or `CooldownTypes.Burst` policy. |
| `CooldownValue` | Required with `CooldownType`; contains the move-specific cooldown variables. |
| `CooldownOnCancel` | Starts the configured cooldown after a cancelled execution. Defaults to `false`. |

Action names only need to be unique inside their provider. Action IDs must be unique across all providers.

## Register the services

Resolve the same provider in both realm ServiceBags before initialization.

```luau
-- Server
const GeneralInputActions = require("@game/ReplicatedStorage/Packages/GeneralInputActions")
const PlayerInputService = require("@game/ServerStorage/ServerPackages/PlayerInputService")

const actions = serviceBag:GetService(GeneralInputActions)
const playerInputs = serviceBag:GetService(PlayerInputService)
```

```luau
-- Client
const GeneralInputActions = require("@game/ReplicatedStorage/Packages/GeneralInputActions")
const PlayerInputServiceClient = require("@game/ReplicatedStorage/Packages/PlayerInputServiceClient")

const actions = serviceBag:GetService(GeneralInputActions)
const playerInputs = serviceBag:GetService(PlayerInputServiceClient)
```

The provider publishes its keymaps through `InputKeyMapRegistryServiceShared`, so settings and input-hint systems can
continue using the existing keymap APIs.

Keep the action object returned by the provider, or retrieve it by name:

```luau
const interact = actions:GetAction("INTERACT")
const charge = actions:GetAction("CHARGE")
```

Pass these registered action objects to the service APIs. Do not reconstruct action tables in gameplay code.

The examples use a server-authoritative `Gameplay` context. Push it for each
player during the corresponding gameplay lifetime:

```luau
playerMaid:Add(playerInputs:PushPlayerContext(player, "Gameplay"))
```

The effective server context is mirrored automatically. Do not repeat the same
push on the client. Use client `PushContext()` only for local overlays such as a
menu or targeting mode.

## NPC actors

Players are registered automatically. Register a persistent Humanoid NPC Model
for the same lifetime as its AI controller:

```luau
const PlayerInputResults = require("@game/ReplicatedStorage/Packages/PlayerInputResults")

npcMaid:Add(playerInputs:RegisterActor(npc))
npcMaid:Add(playerInputs:PushActorContext(npc, "Gameplay"))
```

The NPC Model is its own actor, condition adornee, cooldown owner, lock owner,
and action-execution actor unless the game deliberately chooses another
`Instance` for one of those roles.

AI triggers the same shared action objects used by Players:

```luau
const result = playerInputs:TriggerActorInput(npc, punchAction, "Begin")
if result ~= PlayerInputResults.Accepted then
	return result
end

return PlayerInputResults.Accepted
```

For held actions, send the same lifecycle as a Player:

```luau
playerInputs:TriggerActorInput(npc, barrageAction, "Begin")
playerInputs:TriggerActorInput(npc, barrageAction, "End")
```

Use `"Cancel"` when the AI abandons the action. Context changes, restrictions,
forced release, actor cleanup, or destruction also cancel accepted held states.

`TriggerActorInput()` returns:

| Result | Meaning |
| --- | --- |
| `Accepted` | The state was accepted and emitted to observers. |
| `ActorNotRegistered` | The actor registration is not active. |
| `ActionNotRegistered` | The action object is not the registered catalog object. |
| `ActionNotServerEnabled` | The action omitted `Network`. |
| `StateNotAllowed` | The action does not accept that Begin/End/Cancel state. |
| `ContextDenied` | The current actor context does not allow the action. |
| `RestrictionDenied` | An actor restriction denies the action. |
| `InputModeDenied` | A Player's validated device mode is not allowed; NPCs skip this check. |
| `ConditionFailed` | The action's adornee conditions fail against the Player character or NPC Model. |
| `RateLimited` | The global actor or per-action token bucket rejected the attempt. |
| `AlreadyHeld` | A held action received a duplicate Begin. |
| `NotHeld` | A held action received End or Cancel without an accepted Begin. |

NPC contexts and restrictions remain server-only. NPCs do not use keymaps,
rebinding, client prediction, `PlayerInputMode`, or the PlayerInput network
protocol.

## Observe actions

Use the action object returned by the provider:

```luau
const interact = actions:GetAction("INTERACT")

maid:Add(playerInputs:ObserveInput(interact):Subscribe(function(state)
	print("Local interact state:", state)
end))
```

Client states are `"Begin"`, `"End"`, and `"Cancel"`. `Cancel` occurs when an active action becomes unavailable or is
rebound.

On the server, the first value is an `InputActor`, which is a `Player` or
Humanoid NPC `Model`:

```luau
maid:Add(playerInputs:ObserveInput(interact):Subscribe(function(actor, state)
	if state == "Begin" then
		print(actor.Name, "requested interaction")
	end
end))
```

The server also provides:

- `ObserveAllInputs()` for every accepted actor action;
- `ObserveInput(action)` for one action across every actor;
- `ObserveActorInput(actor, action)` for one actor and action; and
- `ObservePlayerInput(player, action)` as the Player compatibility alias.

Observe every local input when building input diagnostics or an activity tracker:

```luau
maid:Add(playerInputs:ObserveAllInputs():Subscribe(function(action, state)
	print(action.ProviderName, action.Name, state)
end))
```

On the server, the same method includes the player:

```luau
maid:Add(playerInputs:ObserveAllInputs():Subscribe(function(actor, action, state)
	print(actor.Name, action.ProviderName, action.Name, state)
end))
```

Use `PlayerInputStates.BEGIN`, `PlayerInputStates.END`, and `PlayerInputStates.CANCEL` if string literals are undesirable.

## Held actions

Give a replicated action both states when the server needs a held lifecycle:

```luau
Network = {
	States = { "Begin", "End" },
	Capacity = 4,
	RefillRate = 2,
}
```

`"Cancel"` is implicit for held actions: it is accepted as a closing state whenever `"End"` is enabled.

Physical and virtual sources are coalesced, so the action begins when its first source is pressed and ends when its last
source is released. This makes charging and channeling logic straightforward:

```luau
const MAX_CHARGE_TIME = 3

local startedAt: { [Instance]: number } = {}

maid:Add(playerInputs:ObserveInput(chargeAction):Subscribe(function(actor, state)
	if state == "Begin" then
		startedAt[actor] = os.clock()
	elseif state == "End" then
		const startTime = startedAt[actor]
		startedAt[actor] = nil

		if startTime then
			const duration = math.clamp(os.clock() - startTime, 0, MAX_CHARGE_TIME)
			releaseChargedAction(actor, duration)
		end
	elseif state == "Cancel" then
		startedAt[actor] = nil
	end
end))
```

Measure charge time on the server and clamp it to a game-defined maximum. Never accept a client-supplied duration.

Use `IsInputHeld(action)` and `ObserveIsInputHeld(action)` on the client. The server equivalents are
`IsPlayerInputHeld(player, action)` and `ObserveIsPlayerInputHeld(player, action)`.

For example, a client charge indicator can react without maintaining another boolean:

```luau
maid:Add(playerInputs:ObserveIsInputHeld(chargeAction):Subscribe(function(isHeld)
	chargeBar.Visible = isHeld
end))
```

Server systems can observe one player's held state:

```luau
maid:Add(playerInputs:ObserveIsPlayerInputHeld(player, blockAction):Subscribe(function(isBlocking)
	blockState:SetValue(isBlocking)
end))
```

The client can call `ForceReleaseInput(action)` or `ForceReleaseAllInputs()`. The server can authoritatively cancel both
realms with `ForceReleasePlayerInput(player, action)` or `ForceReleaseAllPlayerInputs(player)`. A forced release emits
`"Cancel"` rather than `"End"`, so gameplay code can discard a charge instead of completing it.

Useful forced-release moments include death, stun, respawn, round transitions, entering a menu, losing tool ownership,
and destroying a touch controller while its button is still held:

```luau
playerInputs:ForceReleasePlayerInput(player, chargeAction)
playerInputs:ForceReleaseAllPlayerInputs(player)
```

## Contexts and restrictions

`Default` is always active at priority `0`. Pushed contexts override it by priority, with the most recent push winning a
tie:

```luau
local removeMenuContext = playerInputs:PushContext("Menu")
maid:Add(removeMenuContext)
```

This is useful for preventing gameplay actions while a menu is open:

```luau
local removeMenuContext: (() -> ())? = nil

local function setMenuOpen(isOpen: boolean)
	if isOpen and not removeMenuContext then
		removeMenuContext = playerInputs:PushContext("Menu")
	elseif not isOpen and removeMenuContext then
		removeMenuContext()
		removeMenuContext = nil
	end
end
```

The server equivalent targets a player and automatically mirrors its effective
context and resulting permissions to that player's client:

```luau
maid:Add(playerInputs:PushPlayerContext(player, "Menu"))
```

Use per-action overlays for temporary restrictions:

```luau
maid:Add(playerInputs:PushPlayerRestriction(player, {
	Priority = 100,
	Actions = { interact },
	Allowed = false,
}))
```

For a stun, deny several actions with one owned cleanup callback:

```luau
const removeStunRestriction = playerInputs:PushPlayerRestriction(player, {
	Priority = 200,
	Actions = { attackAction, blockAction, chargeAction },
	Allowed = false,
})

stunMaid:Add(removeStunRestriction)
playerInputs:ForceReleasePlayerInput(player, chargeAction)
```

Restrictions accept registered action objects or their numeric IDs. Later restrictions win ties, which lets a temporary
higher-priority rule override a broader lower-priority rule:

```luau
maid:Add(playerInputs:PushRestriction({
	Priority = 10,
	Actions = { interact },
	Allowed = false,
}))

maid:Add(playerInputs:PushRestriction({
	Priority = 20,
	Actions = { interact },
	Allowed = true,
}))
```

The highest matching overlay wins. An allow overlay cannot bypass the current context, input mode, or server policy.
Local contexts and restrictions can further reduce permission but cannot expand the server's permission set.

Server and local policy have distinct responsibilities:

- `PushPlayerContext` changes authoritative acceptance and mirrors the effective context into the client's context
  stack.
- `PushPlayerRestriction` changes authoritative acceptance and replicates the resulting allowed-action policy.
- `PushContext` and `PushRestriction` are client-only overlays. They can further reduce permission, but cannot expand
  the server's permission set.
- A replicated action must still pass both policies before server gameplay code receives it.

### Environment and device restrictions

The service infers `PlayerInputModeTypes.KEYBOARD`, `GAMEPAD`, and `TOUCH` from the action's standard keymaps. Use an
explicit allowlist when the keymap list contains more modes than the current environment should permit:

```luau
const PlayerInputModeTypes = require("@game/ReplicatedStorage/Packages/PlayerInputModeTypes")

provider:AddAction({
	Id = 4,
	Name = "PRECISION_AIM",
	InputKeyMapList = precisionAimKeyMapList,
	AllowedPlayerInputModes = {
		PlayerInputModeTypes.KEYBOARD,
		PlayerInputModeTypes.GAMEPAD,
	},
	Network = {
		States = { "Begin", "End" },
		Capacity = 3,
		RefillRate = 1,
	},
})
```

This prevents the action from beginning in touch mode even if the keymap list contains a touch binding.

## Rebinding

Client rebinds are local preferences:

```luau
playerInputs:SetBinding(interact, InputModeTypes.KeyboardAndMouse, {
	Enum.KeyCode.F,
})

playerInputs:ClearBinding(interact, InputModeTypes.KeyboardAndMouse)
```

`ClearBinding` restores the default unless a server override exists. This package does not persist or send local
preferences; a game can save them separately.

Modifier chords are supported:

```luau
const InputChordUtils = require("@game/ReplicatedStorage/Packages/InputChordUtils")

playerInputs:SetBinding(openMap, InputModeTypes.KeyboardAndMouse, {
	InputChordUtils.createModifierInputChord({
		Enum.KeyCode.LeftControl,
	}, Enum.KeyCode.M),
})
```

Restore all local preferences for one action or for the complete catalog:

```luau
playerInputs:RestoreBindings(interact)
playerInputs:RestoreBindings()
```

The server can apply a session-authoritative override:

```luau
playerInputs:SetPlayerBindingOverride(player, interact, InputModeTypes.KeyboardAndMouse, {
	Enum.KeyCode.G,
})

playerInputs:ClearPlayerBindingOverride(player, interact, InputModeTypes.KeyboardAndMouse)
```

Server overrides take precedence over local preferences and may affect non-rebindable actions. Removing an override
restores the player's local preference or the action default.

Clear every server override for a player when leaving a temporary control scheme:

```luau
playerInputs:ClearPlayerBindingOverrides(player)
```

The effective precedence is:

```text
server override > local preference > action default
```

Binding conflicts are allowed. Use `ContextActionPriority` and `ConsumeInput` on action definitions when order or
exclusive handling matters.

For example, a modal confirmation action can win over ordinary interaction:

```luau
ContextActionPriority = Enum.ContextActionPriority.High.Value,
ConsumeInput = true,
```

## Move-specific character conditions

An action may declare an `AdorneeConditionContext` builder evaluated against
the player's current character on both client and server. PlayerInput creates
and owns a fresh container for the action, then passes it to the builder:

```luau
const AdorneeConditionUtils = require("@game/ReplicatedStorage/Packages/AdorneeConditionUtils")

provider:AddAction({
	Id = 20,
	Name = "PUNCH",
	InputKeyMapList = punchKeyMapList,
	AdorneeConditionContext = function(conditionContainer)
		AdorneeConditionUtils.createRequiredAttribute("CanAttack", true).Parent = conditionContainer
		AdorneeConditionUtils.createRequiredAttribute("IsStunned", false).Parent = conditionContainer
	end,
	ConsumeInputWhenConditionFails = true,
})
```

When no character exists, configured conditions fail closed. A failed condition
rejects new `Begin` events without releasing an input that was already held.
Set `ConsumeInputWhenConditionFails` to sink denied physical input and prevent a
lower-priority binding on the same key from running. Omit it to allow normal
priority fall-through. Each action gets its own container automatically, so the
builder only needs to add that move's conditions.

## Headless touch and virtual inputs

Enum and modifier-chord bindings execute automatically. The package intentionally does not render touch UI. A touch or
gesture controller can trigger a currently bound `Tap`, `Drag`, `TouchButton`, or slotted touch value:

```luau
const touchBinding = SlottedTouchButtonUtils.createSlottedTouchButton("primary1")

touchButton.Activated:Connect(function()
	playerInputs:TriggerInput(interact, touchBinding, "Begin")
	playerInputs:TriggerInput(interact, touchBinding, "End")
end)
```

`TriggerInput` returns `false` if the virtual value is not bound in the active input mode or the action is restricted.

Use separate press and release events for held touch actions:

```luau
const chargeTouchBinding = SlottedTouchButtonUtils.createSlottedTouchButton("primary2")

maid:Add(chargeButton.MouseButton1Down:Connect(function()
	playerInputs:TriggerInput(chargeAction, chargeTouchBinding, "Begin")
end))

maid:Add(chargeButton.MouseButton1Up:Connect(function()
	playerInputs:TriggerInput(chargeAction, chargeTouchBinding, "End")
end))

maid:Add(function()
	playerInputs:ForceReleaseInput(chargeAction)
end)
```

The cleanup release is important when UI disappears before Roblox delivers the corresponding button-up event.

Other supported virtual values include `"Tap"`, `"Drag"`, `"TouchButton"`, and values created by
`SlottedTouchButtonUtils`.

## Common recipes

### Interaction request

Use a Begin-only network action, then validate the world state on the server:

```luau
maid:Add(playerInputs:ObserveInput(interact):Subscribe(function(actor, state)
	if state ~= "Begin" then
		return
	end
	if not actor:IsA("Player") then
		return
	end

	const target = interactionService:GetCurrentTarget(actor)
	if target and interactionService:CanInteract(actor, target) then
		interactionService:Interact(actor, target)
	end
end))
```

### Sprint

Use Begin/End and always handle Cancel like a release:

```luau
maid:Add(playerInputs:ObserveInput(sprint):Subscribe(function(actor, state)
	if not actor:IsA("Player") then
		return
	end

	if state == "Begin" then
		if staminaService:CanSprint(actor) then
			sprintService:SetSprinting(actor, true)
		else
			playerInputs:ForceReleasePlayerInput(actor, sprint)
		end
	else
		sprintService:SetSprinting(actor, false)
	end
end))
```

When stamina is exhausted:

```luau
playerInputs:ForceReleasePlayerInput(player, sprint)
```

### Vehicle controls

Declare a high-priority `Vehicle` context and push it for the same lifetime as the player's seat:

```luau
vehicleMaid:Add(playerInputs:PushPlayerContext(player, "Vehicle"))
vehicleMaid:Add(function()
	playerInputs:ForceReleaseAllPlayerInputs(player)
end)
```

Give driving actions `AllowedContexts = { "Vehicle" }` and ordinary character actions
`AllowedContexts = { "Gameplay" }`.

### Cutscenes and round transitions

Use one high-priority deny restriction and force-release existing held actions:

```luau
roundMaid:Add(playerInputs:PushPlayerRestriction(player, {
	Priority = 1_000,
	Actions = gameplayActions,
	Allowed = false,
}))

playerInputs:ForceReleaseAllPlayerInputs(player)
```

## Network boundary

The gameplay packet contains only:

```text
uint8  packetId
uint16 actionId
uint8  state
```

With ByteNet framing, one input report is four bytes before Roblox transport overhead. Server policy updates use
revisioned add/remove ID deltas; the complete allowlist is sent only in the initial-state response.

The server checks action registration, replication policy, context, restrictions, the last validated
`PlayerInputMode`, and held-state transitions. Begin reports also pass through global per-player and per-action token
buckets. A valid End report remains able to close a previously accepted held action. Invalid attempts are silently
dropped.

The default global guard has capacity `60` and refills at `30` events per second. Configure it before `Start`:

```luau
playerInputs:SetGlobalServerInputRateLimit(40, 20)
```

`SetGlobalNetworkRateLimit()` remains as the Player compatibility alias.

Each replicated action also has its own bucket:

- `Capacity` is the maximum burst of accepted Begin attempts.
- `RefillRate` is the number of tokens restored per second.
- End and Cancel are not charged against the per-action bucket, so a valid held action can always close.

Choose limits from the action's actual cadence. An interaction may allow a small burst, while a deliberate ultimate
ability should have a much smaller bucket. Rate limits are abuse guards, not gameplay cooldowns.

## Cooldowns

Cooldowns are optional. Neither core PlayerInput service resolves
`CooldownService`. Games that resolve `PlayerInputCooldownService` and its
client counterpart get automatic cooldown restrictions for every configured
action. The authoritative execution wrapper checks the cooldown and starts it
after successful work, so ordinary gameplay handlers do not bind, check, start,
or predict cooldowns themselves.

### Define cooldown behavior

Put an optional move-specific cooldown directly on the action. `CooldownType`
and `CooldownValue` must either both be present or both be omitted:

```luau
const CooldownTypes = require("@game/ReplicatedStorage/Packages/CooldownTypes")

const punchAction = provider:AddAction({
	Id = 20,
	Name = "PUNCH",
	InputKeyMapList = punchInputKeyMapList,
	Network = {
		States = { "Begin" },
		Capacity = 8,
		RefillRate = 4,
	},
	CooldownType = CooldownTypes.Burst,
	CooldownValue = {
		Duration = 0.5,
		Count = 4,
		Window = 3,
		PenaltyDuration = 3,
	},
	CooldownOnCancel = false,
})
```

This example uses a `0.5` second cooldown normally. The fourth successful punch
inside a rolling three-second window receives a three-second cooldown and
resets the burst history. A normal cooldown uses the same shape:

```luau
const dashAction = provider:AddAction({
	Id = 21,
	Name = "DASH",
	InputKeyMapList = dashInputKeyMapList,
	Network = {
		States = { "Begin" },
		Capacity = 3,
		RefillRate = 2,
	},
	CooldownType = CooldownTypes.Default,
	CooldownValue = {
		Duration = 2,
	},
})
```

The cooldown definition variables are:

| Variable | Type | Purpose |
| --- | --- | --- |
| `CooldownType` | `CooldownTypes.Default` or `CooldownTypes.Burst` | Selects how `CooldownValue` is validated and applied. |
| `CooldownValue` | table | Carries the variables for the selected cooldown type. It is always a table, including default cooldowns. |
| `CooldownOnCancel` | boolean | Optional. A cancelled `ActionExecution` consumes the cooldown when `true`; defaults to `false`. |
| `action.CooldownKey` | generated `string` | Stable move key in `ProviderName.ActionName` form, such as `Combat.PUNCH`. |

`CooldownValue` supports:

| Variable | Cooldown type | Purpose |
| --- | --- | --- |
| `Duration` | Default and Burst | Positive base cooldown duration in seconds. |
| `Count` | Burst only | Integer of at least `2`; this successful use count triggers the penalty. |
| `Window` | Burst only | Positive rolling-window duration in seconds. |
| `PenaltyDuration` | Burst only | Positive threshold cooldown in seconds; it must be longer than `Duration`. |

The provider validates and freezes `CooldownValue`. Cooldown history and active
state remain isolated by actor and `action.CooldownKey`. Player cooldowns
therefore survive character respawns, while an NPC Model's cooldowns end with
that actor lifetime.

### Automatic input restrictions

Resolve the two optional bridge services once in the realm ServiceBags:

```luau
-- Server
const PlayerInputCooldownService = require("@game/ServerStorage/ServerPackages/PlayerInputCooldownService")

-- In Init
self._playerInputCooldownService = self._serviceBag:GetService(PlayerInputCooldownService)
```

```luau
-- Client
const PlayerInputCooldownServiceClient = require("@game/ReplicatedStorage/Packages/PlayerInputCooldownServiceClient")

-- In Init
self._playerInputCooldownServiceClient = self._serviceBag:GetService(PlayerInputCooldownServiceClient)
```

That is all the setup needed. The server bridge discovers every registered
Player and NPC actor and binds each action that declares a cooldown. The client
bridge discovers the same action catalog and binds the local Player. When an
authoritative cooldown begins, both bridges push a deny restriction; if the
action is held, the policy refresh releases it with `"Cancel"`.

The generated action cooldown uses the actor as its owner. Several actions can
still share an additional manually named cooldown through the lower-level
`Bind()` API:

```luau
actorMaid:Add(self._playerInputCooldownService:Bind({
	Actor = actor,
	Owner = actor,
	Key = "SharedPrimary",
	Actions = { defaultPrimary, standPrimary, specPrimary },
}))
```

One grouped binding changes PlayerInput policy once when the shared cooldown
starts or ends.

### Execute and start automatically

Use `TryStartActionExecution()` from the authoritative input handler. It checks
the action's cooldown, applies the optional actor-local lock, invokes the
cancellable callback, and watches its result:

```luau
self._maid:Add(self._playerInputs:ObserveInput(punchAction):Subscribe(function(actor, state)
	if state ~= "Begin" then
		return
	end

	self._playerInputCooldownService:TryStartActionExecution(punchAction, {
		Actor = actor,
		Tags = { "Combat", "Punch" },
		Timeout = 2,
		Lock = {
			Key = "CombatAction",
		},
	}, function(cancelToken)
		return self:_performPunchAsync(actor, cancelToken)
	end)
end))
```

The callback must return a `Promise`:

| Terminal status | Starts the action cooldown? |
| --- | --- |
| `Succeeded` | Yes |
| `Cancelled` | Only when the action sets `CooldownOnCancel = true` |
| `Failed` | No |
| `TimedOut` | No |

Only successful executions advance burst history. Use an execution lock when
work yields or when actions must not overlap; the cooldown begins after
completion and is not an in-progress reservation.

For a charge, barrage, or block, keep the callback Promise pending after
`"Begin"` and resolve it after a successful `"End"`. On `"Cancel"`, stun, death,
or another interruption, cancel the execution. This makes the final execution
status—not the raw input state—the single cooldown decision.

### Optional client prediction

Automatic binding does not require client prediction. Prediction is an optional
latency optimization and never authorizes gameplay. It immediately activates
the already-configured client restriction while authoritative state is in
transit:

```luau
self._maid:Add(self._playerInputs:ObserveInput(punchAction):Subscribe(function(state)
	if state ~= "Begin" then
		return
	end

	const cancelPrediction =
		self._playerInputCooldownServiceClient:PredictActionCooldown(Players.LocalPlayer, punchAction)

	-- Keep cancelPrediction if the game has an acknowledgement path. Call it
	-- when the server rejects this use.
end))
```

An accepted authoritative cooldown replaces the prediction automatically. A
burst prediction begins with `Duration`; if that use triggers
`PenaltyDuration`, replicated server state corrects it. If the server rejects
the action, call the returned idempotent cleanup through a game-owned
acknowledgement path. Without an acknowledgement, the prediction expires after
its predicted duration.

PlayerInput token buckets and cooldowns are separate safeguards. Token buckets
limit packet abuse; cooldowns enforce game rules. The execution wrapper always
performs the server cooldown check even when client prediction is enabled.

## Optional action locks and cancellation

`ActionExecutionService` is also opt in and remains outside the core input
service. Cooldown-backed actions normally enter it through
`TryStartActionExecution()`. Use one shared lock key for moves that must not
overlap:

```luau
const execution = self._playerInputCooldownService:TryStartActionExecution(action, {
	Actor = player,
	Tags = { "Combat", action.Name },
	Timeout = 8,
	Lock = {
		Key = "CombatAction",
	},
}, function(cancelToken)
	return self:_performMoveAsync(player, action, cancelToken)
end)

if not execution then
	return -- This player is already using another CombatAction move.
end
```

The actor automatically owns the lock. Move A and Move B block each other for
the same player when both use `"CombatAction"`, while a different player can
use that key concurrently. Cancel dynamically by handle, actor, runtime tag, or
actor/key:

```luau
execution:Cancel("Interrupted")
self._actionExecutions:CancelActorExecutionsByTag(player, "Combat", "Stunned")
self._actionExecutions:CancelActorLockExecution(player, "CombatAction", "Died")
```

Cancellation is cooperative: the callback receives a read-only `CancelToken`,
and the lock remains held until its Promise settles or the required timeout
expires. See the `actionexecutionservice` README for the complete lifecycle.

## Trust boundary reminder

Only the compact action ID and state are sent for gameplay input:

```text
client
  -> uint16 actionId
  -> uint8 state
server
  -> validate registration, policy, mode, state transition, and rate limits
```

Raw key codes, input objects, local context stacks, and local binding preferences are not transmitted with each input.

Input reports are requests, not proof that physical hardware produced an event. Gameplay code must still validate
distance, ownership, cooldowns, character state, and every other domain rule before performing an authoritative action.

## API quick reference

### Client

| Method | Purpose |
| --- | --- |
| `ObserveAllInputs()` | Observe every locally accepted action and state. |
| `ObserveInput(action)` | Observe one local action. |
| `IsInputHeld(action)` | Read the current local held state. |
| `ObserveIsInputHeld(action)` | Observe the current local held state. |
| `SetBinding(action, mode, inputs)` | Set a local binding preference. |
| `ClearBinding(action, mode)` | Clear one local preference. |
| `RestoreBindings(action?)` | Clear local preferences for one or all actions. |
| `TriggerInput(action, input, state)` | Drive a bound virtual or touch input. |
| `ForceReleaseInput(action)` | Cancel one locally held action. |
| `ForceReleaseAllInputs()` | Cancel every locally held action. |
| `PushContext(name)` | Push a local context overlay until cleanup. |
| `PushRestriction(config)` | Push a local restriction until cleanup. |

### Server

| Method | Purpose |
| --- | --- |
| `RegisterActor(actor)` | Register a scoped Humanoid NPC actor; Players register automatically. |
| `ObserveActorsBrio()` | Observe each Player or registered NPC for its authoritative input lifetime. |
| `TriggerActorInput(actor, action, state)` | Attempt an authoritative NPC or Player action state. |
| `ObserveAllInputs()` | Observe every accepted actor action. |
| `ObserveInput(action)` | Observe one action across all actors. |
| `ObserveActorInput(actor, action)` | Observe one actor and action. |
| `IsActorInputHeld(actor, action)` | Read authoritative held state. |
| `ObserveIsActorInputHeld(actor, action)` | Observe authoritative held state. |
| `PushActorContext(actor, name)` | Push an authoritative actor context. |
| `PushActorRestriction(actor, config)` | Push an authoritative actor restriction. |
| `ForceReleaseActorInput(actor, action)` | Cancel one held actor action. |
| `ForceReleaseAllActorInputs(actor)` | Cancel every held actor action. |
| `SetPlayerBindingOverride(...)` | Apply a session-authoritative binding. |
| `ClearPlayerBindingOverride(...)` | Remove one authoritative binding. |
| `ClearPlayerBindingOverrides(player)` | Remove all authoritative bindings. |
| `SetGlobalServerInputRateLimit(capacity, refill)` | Configure the per-actor guard before `Start`. |

The existing `ObservePlayerInput`, held-state, context, restriction,
force-release, and `SetGlobalNetworkRateLimit` names remain Player-only
compatibility aliases.

### Optional move cooldown integration

| Realm | Method | Purpose |
| --- | --- | --- |
| Server | `TryStartActionExecution(action, config, callback)` | Check, execute, and start the configured cooldown according to the terminal result. |
| Server | `IsActionOnCooldown(owner, action)` | Check the action's generated cooldown key. |
| Server | `StartActionCooldown(owner, action)` | Start the action's configured default or burst cooldown. |
| Client | `IsActionOnCooldown(owner, action)` | Check effective authoritative or predicted state. |
| Client | `PredictActionCooldown(owner, action)` | Predict the configured base cooldown and return its cancellation callback. |

`BindAction()` remains as a compatibility-level explicit API, but normal
actor-owned action cooldowns should rely on automatic registration on both
realms.

These methods belong to `PlayerInputCooldownService` and
`PlayerInputCooldownServiceClient`, not the core PlayerInput services.

## Operational notes

- Own every pushed context and restriction callback with a `Maid`.
- Treat input `"Cancel"` as cleanup; opt into a cooldown for the resulting
  cancelled execution with `CooldownOnCancel`.
- Use Begin/End for anything whose duration matters.
- Keep local-only actions off the network by omitting `Network`.
- Keep action IDs stable and identical in the server and client provider.
- Reuse the same registered action object when calling service APIs.
- Persist local binding preferences separately if they should survive sessions.
- Validate gameplay rules after an input reaches the server.
