# CancelToken

`CancelToken` is the read-only side of cooperative cancellation.
`CancelTokenSource` owns the authority to request cancellation:

```luau
const source = CancelTokenSource.new()
const token = source:GetToken()

token.Cancelled:Connect(function()
	print("Cancelled:", token:GetReason())
end)

source:Cancel("Stunned")
```

Cancellation is one-shot and preserves its first reason. Existing
`CancelToken.new(executor)`, `fromMaid()`, `fromSeconds()`, `Cancelled`, and
`PromiseCancelled` APIs remain available.

Cancellation does not terminate arbitrary Luau code. Work must observe the
token, stop its owned resources, and settle its Promise.
