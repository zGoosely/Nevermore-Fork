--!strict
--[=[
	Contracts for cancellable server action execution.

	@types ActionExecutionTypes
]=]
const CancelToken = require("@game/ReplicatedStorage/Packages/CancelToken")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")

export type Status = "Running" | "Cancelling" | "Succeeded" | "Failed" | "Cancelled" | "TimedOut"

export type LockConfig = {
	Key: string,
}

export type ExecutionConfig = {
	Actor: Instance,
	Tags: { string }?,
	Timeout: number,
	Lock: LockConfig?,
}

export type ExecutionCallback = (cancelToken: CancelToken.CancelToken) -> Promise.Promise<any>

return {}
