--!strict
--[=[
	Shared contracts for keyed server lock acquisition.

	@types LockServiceTypes
]=]

const require = require("../Loader").load()

const Promise = require("Promise")

export type AcquireConfig = {
	Owner: Instance,
	Key: string,
	Holder: Instance?,
	Timeout: number,
}

export type LockCallback = () -> Promise.Promise<any>

return {}
