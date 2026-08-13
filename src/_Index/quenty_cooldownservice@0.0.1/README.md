# CooldownService

`CooldownService` is a small, category-free cooldown package. A cooldown belongs
to any `Instance` and a case-sensitive string key, so the same API can cover
combat moves, tools, interactions, UI, matchmaking, or any other temporary
lockout.

The server is authoritative. Cooldowns use `TimeSyncService` timestamps and
replicate as tagged Folders when their owner replicates. The client can query
that state and may create temporary predictions for responsive UI and input
suppression.

Nothing automatically depends on this package. The PlayerInput integration services are
opt-in modules, and `PlayerInputService` does not require `CooldownService`.

## Setup

Resolve the realm-appropriate service from your existing `ServiceBag`:

```luau
-- Server
const CooldownService = require("@game/ReplicatedStorage/Packages/CooldownService")

function CombatService.Init(self, serviceBag)
	self._cooldownService = serviceBag:GetService(CooldownService)
end
```

```luau
-- Client
const CooldownServiceClient = require("@game/ReplicatedStorage/Packages/CooldownServiceClient")

function CombatController.Init(self, serviceBag)
	self._cooldownServiceClient = serviceBag:GetService(CooldownServiceClient)
end
```

The services resolve `TimeSyncService` and their binder providers internally.
Use the public APIs after the `ServiceBag` has started.

## Check, execute, then start

Cooldowns deliberately do not execute game behavior. Check the cooldown, run
your authoritative game validation, and start the cooldown only after the
action succeeds:

```luau
function CombatService.TryHeavyPunch(self, player: Player): boolean
	const key = "HeavyPunch"

	if self._cooldownService:IsOnCooldown(player, key) then
		return false
	end

	if not self:_canHeavyPunch(player) then
		return false
	end

	self:_performHeavyPunch(player)

	const cooldown = self._cooldownService:StartCooldown(player, key, 5)
	return cooldown ~= nil
end
```

`StartCooldown()` returns `nil` and preserves the current cooldown when that
owner/key pair is already active. `RestartCooldown()` is the explicit
administrative override.

The check-execute-start sequence is intentionally not a transaction. If the
action yields, use a game-owned reservation or concurrency guard so two
requests cannot execute while both are waiting.

## Typed and burst cooldowns

Use `StartTypedCooldown()` when a definition selects its cooldown behavior at
runtime. Values always use a table, including ordinary cooldowns:

```luau
const CooldownTypes = require("@game/ReplicatedStorage/Packages/CooldownTypes")

cooldownService:StartTypedCooldown(player, "Dash", CooldownTypes.Default, {
	Duration = 2,
})
```

A burst cooldown uses its base duration until enough successful starts occur
inside a rolling window. The threshold start uses the penalty duration and
then resets the history:

```luau
cooldownService:StartTypedCooldown(player, "Punch", CooldownTypes.Burst, {
	Duration = 0.5,
	Count = 4,
	Window = 3,
	PenaltyDuration = 3,
})
```

Only accepted starts advance the burst. Active cooldown rejections do not.
Histories are isolated by owner and key, remain session-only, and are cleared
by administrative restart or clear operations.

## Querying and changing cooldowns

```luau
const cooldown = cooldownService:StartCooldown(player, "Dash", 3)
if cooldown then
	print(cooldown:GetStartedAt(), cooldown:GetEndsAt())

	cooldown:AddTime(1)
	cooldown:RemoveTime(0.25)
	cooldown:Restart(2)
	cooldown:Clear()
end
```

The service also provides:

```luau
cooldownService:GetCooldown(owner, "Dash")
cooldownService:IsOnCooldown(owner, "Dash")
cooldownService:GetRemainingTime(owner, "Dash")
cooldownService:ClearCooldown(owner, "Dash")
```

All durations and adjustments are finite positive numbers. Removing all
remaining time clears the cooldown.

## Choosing an owner

The owner controls both organization and lifetime:

- Use a `Player` for cooldowns that should survive character respawns.
- Use a character for cooldowns that should reset with that character.
- Use a `Tool` for state owned by one equipped item.
- Use a replicated configuration or ability Folder for shared world state.
- Use a local UI Instance for client-only predicted presentation state.

Reusing a key under the same owner creates a shared cooldown group:

```luau
const GLOBAL_ATTACK = "GlobalAttack"

if not cooldownService:IsOnCooldown(player, GLOBAL_ATTACK) then
	performAttack()
	cooldownService:StartCooldown(player, GLOBAL_ATTACK, 0.4)
end
```

Different owners may use the same key independently.

## Observing cooldowns

Observations emit state changes rather than ticking every frame:

```luau
maid:Add(cooldownServiceClient:ObserveCooldown(player, "Dash"):Subscribe(function(cooldown)
	if cooldown then
		print("Dash ends at", cooldown:GetEndsAt())
	else
		print("Dash is ready")
	end
end))

maid:Add(cooldownServiceClient:ObserveIsOnCooldown(player, "Dash"):Subscribe(function(isCoolingDown)
	dashButton.Active = not isCoolingDown
end))
```

For a smooth progress bar, calculate the display value during rendering from
the model's synchronized timestamps:

```luau
RunService.RenderStepped:Connect(function()
	const cooldown = cooldownServiceClient:GetCooldown(player, "Dash")
	if not cooldown then
		progressBar.Size = UDim2.fromScale(0, 1)
		return
	end

	const remaining = cooldown:GetRemainingTime()
	const progress = remaining / cooldown:GetDuration()
	progressBar.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
end)
```

The package schedules all expiry transitions through one minimum heap and one
heartbeat, rather than creating a timer or render loop for every cooldown.

## Client prediction

Prediction is optional and never authorizes an action:

```luau
const cancelPrediction = cooldownServiceClient:PredictCooldown(player, "Dash", 3)

dashRequest:FireServer()

dashResult.OnClientEvent:Once(function(accepted)
	if not accepted then
		cancelPrediction()
	end
end)
```

When the matching server cooldown replicates, it replaces and cleans up the
prediction automatically. If the server rejects the action, call the returned
idempotent cancellation callback. A prediction also expires naturally if no
server state arrives.

`PredictTypedCooldown()` predicts the base `Duration`. The authoritative
cooldown replaces it with `PenaltyDuration` when the server resolves a burst
threshold.

Before `TimeSyncService` finishes client synchronization, display and prediction
use `tick()` as an estimate. Existing observations are reevaluated through
normal expiry and authoritative reconciliation after synchronized state is
available.

## PlayerInputService integration

The bridge is separate from both core services. Resolve it only in games that
want automatic input restrictions; it resolves CooldownService and
PlayerInputService internally:

```luau
-- Shared action definition
const CooldownTypes = require("@game/ReplicatedStorage/Packages/CooldownTypes")

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

The action receives the generated move-specific key `ProviderName.ActionName`.
Resolve the optional integration services once; they discover configured
actions and bind their restrictions automatically:

```luau
-- Server
const PlayerInputCooldownService = require("@game/ReplicatedStorage/Packages/PlayerInputCooldownService")

function CombatService.Init(self, serviceBag)
	self._playerInputCooldownService = serviceBag:GetService(PlayerInputCooldownService)
end

self._playerInputCooldownService:TryStartActionExecution(dashAction, {
	Actor = actor,
	Tags = { "Movement", "Dash" },
	Timeout = 2,
	Lock = {
		Key = "MovementAction",
	},
}, function(cancelToken)
	return performDashAsync(actor, cancelToken)
end)
```

```luau
-- Client
const PlayerInputCooldownServiceClient = require("@game/ReplicatedStorage/Packages/PlayerInputCooldownServiceClient")

function CombatController.Init(self, serviceBag)
	self._playerInputCooldownServiceClient = serviceBag:GetService(PlayerInputCooldownServiceClient)
end
```

`Actor` may be a Player or registered Humanoid NPC Model. The actor is the
default cooldown owner. Action registration and actor lifetimes automatically
own the server observations; the local Player and shared action catalog
automatically own the client observations.

Several actions can still share a manually named cooldown through `Bind()`:

```luau
const cleanup = self._playerInputCooldownService:Bind({
	Actor = actor,
	Owner = actor,
	Key = "GlobalAttack",
	Actions = {
		actions.StandBarrage,
		actions.SpecBarrage,
		actions.BasicPunch,
	},
})
```

When a mapped cooldown becomes active, the integration service pushes a high-priority deny
restriction. PlayerInput's policy refresh cancels a currently held mapped
action. Set `Priority` in the binding config when a game deliberately needs a
different restriction precedence.

`TryStartActionExecution()` is the authoritative convenience path. It checks
the action cooldown, delegates cancellable work to `ActionExecutionService`,
and starts the typed cooldown when the callback Promise succeeds. A cancelled
execution also starts it when the action declares `CooldownOnCancel = true`.
Failure and timeout do not start it. Direct `IsActionOnCooldown()` and
`StartActionCooldown()` remain available for workflows that do not use
`ActionExecution`.

### Charging and release actions

For a charged action, keep the execution Promise pending and resolve it at the
successful release point:

```luau
playerInputService:ObservePlayerInput(player, actions.ChargedShot):Subscribe(function(state)
	if state == "Begin" then
		beginChargedShotExecution(player)
		return
	end

	if state == "End" then
		resolveChargedShotExecution(player)
	elseif state == "Cancel" then
		cancelChargedShotExecution(player, "InputCancelled")
	end
end)
```

If some other system starts the cooldown while the action is held, the optional
PlayerInput binding cancels that held action.

## RateLimiter and token buckets

Rate limits and gameplay cooldowns solve different problems:

1. PlayerInput's client token bucket avoids unnecessary packets.
2. PlayerInput's server token bucket rejects abusive traffic.
3. `TryStartActionExecution()` checks the authoritative cooldown.
4. The game validates and executes the operation.
5. The wrapper starts the cooldown from the successful or opted-in cancelled
   terminal result.

The server must keep step 3 even when the optional input bridge is active.
Client restrictions improve responsiveness and reduce traffic, but clients are
not trusted to enforce gameplay cooldowns.

## Advanced Folder creation

Most callers should use `StartCooldown()` or `PredictCooldown()`.
`CooldownServiceUtils.createCooldown(owner, key, duration, clock)` is available
for systems that intentionally create tagged cooldown Folders directly. It
initializes every attribute before tagging and parenting the Folder. Calls made
on the server create authoritative state; calls made on a client create local
predicted state.

## Lifetime and persistence

The server destroys expired cooldown Folders. Client mirrors treat an
authoritative cooldown as expired at its synchronized timestamp even if the
destroy replication arrives later.

Cooldowns are session state. They do not write to a datastore or survive
teleports. A game that needs persistent lockouts should save an absolute end
timestamp itself and recreate the cooldown after validating the loaded value.
