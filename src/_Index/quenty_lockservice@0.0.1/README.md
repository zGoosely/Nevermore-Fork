# LockService

`LockService` provides server-local, non-queued locks identified by an owner
`Instance` and string key. `ActionExecutionService` always uses the action's
actor as this owner, so action locks never contend across different players.

```luau
const permit = lockService:TryAcquire({
	Owner = player,
	Key = "CombatAction",
	Holder = player,
	Timeout = 8,
})

if not permit then
	return -- Another holder owns this lock; do not queue stale intent.
end

operationAsync():Finally(function()
	permit:Release()
end)
```

For a shorter promise-based path, `RunAsync()` releases automatically and
returns nil when that owner/key is already held:

```luau
const promise = lockService:RunAsync({
	Owner = player,
	Key = "InventoryMutation",
	Timeout = 5,
}, function()
	return updateInventoryAsync(player)
end)
```

Every acquisition requires a finite positive timeout. A permit also releases
when its owner or optional holder is destroyed. `Release()` is idempotent, and
`GetReleaseReason()` distinguishes explicit release, timeout, and lifecycle
cleanup.

Locks are session state. They do not replicate, persist, or authorize gameplay.
The server must still validate the action before acquiring a permit.
