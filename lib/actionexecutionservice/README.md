# ActionExecutionService

`ActionExecutionService` runs cancellable server work with optional keyed locks.
It is independent from `PlayerInputService`: input reports intent, while the
gameplay system decides whether work succeeded, failed, or should be cancelled.

Resolve it normally during `Init`; it resolves `LockService` internally:

```luau
const ActionExecutionService = require("ActionExecutionService")

function CombatService.Init(self, serviceBag)
	self._actionExecutions = serviceBag:GetService(ActionExecutionService)
end
```

## Start protected work

`TryStart()` returns nil without invoking the callback when the actor already
has the same lock key. Locks are actor-local: another Player or NPC can hold the
same key at the same time.

```luau
const execution = self._actionExecutions:TryStart({
	Actor = player,
	Tags = { "Combat", "Barrage" },
	Timeout = 8,
	Lock = {
		Key = "CombatAction",
	},
}, function(cancelToken)
	return self:_performBarrageAsync(player, cancelToken)
end)

if not execution then
	return -- This player is already performing another CombatAction.
end

execution:GetPromise():Then(function()
	print("Barrage succeeded")
end, function(reason)
	print("Barrage did not complete:", reason)
end)
```

The callback must return a `Promise`. Resolution means success; rejection means
failure. Either result releases the lock.

## Cooperative cancellation

The callback receives a read-only `CancelToken`. Long-running work must observe
it and stop its own animation, loop, connection, or pending Promise:

```luau
function CombatService._performBarrageAsync(self, player, cancelToken)
	const promise = Promise.new()
	const maid = Maid.new()

	maid:Add(cancelToken.Cancelled:Connect(function()
		self:_stopBarrage(player)
		promise:Reject(cancelToken:GetReason())
	end))

	maid:Add(self:_beginBarrage(player, function()
		promise:Resolve()
	end))

	promise:Finally(function()
		maid:DoCleaning()
	end)
	return promise
end
```

`execution:Cancel("Stunned")` signals cancellation but deliberately retains the
lock until the callback settles. The required timeout is the final safeguard
for uncooperative code; timeout force-finalizes the execution and releases its
lock.

Runtime tags make interruption dynamic:

```luau
self._actionExecutions:CancelActorExecutionsByTag(player, "Combat", "Stunned")
self._actionExecutions:CancelActorExecutions(player, "Died")
self._actionExecutions:CancelActorLockExecution(player, "CombatAction", "Interrupted")
```

Tags belong to each execution rather than its input definition, so one input
action can use different cancellation groups based on state, target, or mode.

## PlayerInput integration

Core input remains independent from execution. When an action declares
`CooldownType` and `CooldownValue`, use the optional
`PlayerInputCooldownService` wrapper so cooldown binding, checking, and terminal
result handling stay automatic:

```luau
self._maid:Add(self._playerInputs:ObserveInput(barrageAction):Subscribe(function(actor, state)
	if state == "Begin" then
		self._barrageExecutions[actor] = self._playerInputCooldownService:TryStartActionExecution(barrageAction, {
			Actor = actor,
			Tags = { "Combat", "Barrage" },
			Timeout = 8,
			Lock = {
				Key = "CombatAction",
			},
		}, function(cancelToken)
			return self:_performBarrageAsync(actor, cancelToken)
		end)
	elseif state == "End" or state == "Cancel" then
		const execution = self._barrageExecutions[actor]
		if execution then
			if state == "End" then
				self:_finishBarrage(actor)
			else
				execution:Cancel("InputCancelled")
			end
		end
	end
end))
```

Resolve the barrage Promise in `_finishBarrage()` after a valid release.
Success automatically starts the action cooldown. Cancellation starts it only
when the action declares `CooldownOnCancel = true`; failure and timeout do not.
Actions without a configured cooldown continue using `ActionExecutionService`
directly.

The server remains the cancellation authority. Clients may report ordinary
input states, but they do not own server cancellation tokens or locks.

Statuses are `Running`, `Cancelling`, `Succeeded`, `Failed`, `Cancelled`, and
`TimedOut`. Use `GetStatus()` or `ObserveStatus()` for diagnostics and
orchestration.
