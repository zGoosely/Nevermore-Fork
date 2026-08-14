--!strict
--[=[
	Validates keyed lock configuration and identifiers.

	@util LockServiceUtils
]=]
const t = require("@game/ReplicatedStorage/Packages/t")

const isAcquireConfigShape = t.strictInterface({
	Owner = t.Instance,
	Key = t.string,
	Holder = t.optional(t.Instance),
	Timeout = t.number,
})

const LockServiceUtils = {}

--[=[
	Returns whether a value is a finite positive duration.

	@within LockServiceUtils
	@param value any
	@return boolean
]=]
function LockServiceUtils.isTimeout(value: any): boolean
	return t.number(value) and value > 0 and value < math.huge
end

--[=[
	Returns whether a value is a nonempty lock key.

	@within LockServiceUtils
	@param value any
	@return boolean
]=]
function LockServiceUtils.isLockKey(value: any): boolean
	return t.string(value) and value ~= ""
end

--[=[
	Returns whether a value is a nonempty release or cancellation reason.

	@within LockServiceUtils
	@param value any
	@return boolean
]=]
function LockServiceUtils.isReason(value: any): boolean
	return t.string(value) and value ~= ""
end

--[=[
	Returns whether a value is a valid acquisition configuration.

	@within LockServiceUtils
	@param value any
	@return boolean
]=]
function LockServiceUtils.isAcquireConfig(value: any): boolean
	return isAcquireConfigShape(value)
		and LockServiceUtils.isLockKey(value.Key)
		and LockServiceUtils.isTimeout(value.Timeout)
end

return LockServiceUtils
