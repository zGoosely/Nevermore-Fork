--!strict
--[=[
	Shared contracts for keyed server lock acquisition.

	@types LockServiceTypes
]=]
const Promise = require("@game/ReplicatedStorage/Packages/Promise")

export type AcquireConfig = {
	Owner: Instance,
	Key: string,
	Holder: Instance?,
	Timeout: number,
}

export type LockCallback = () -> Promise.Promise<any>

return {}
