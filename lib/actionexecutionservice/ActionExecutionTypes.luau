--!strict
--[=[
	Contracts for cancellable server action execution.

	@types ActionExecutionTypes
]=]

const require = require("../Loader").load()

const CancelToken = require("CancelToken")
const Promise = require("Promise")

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
