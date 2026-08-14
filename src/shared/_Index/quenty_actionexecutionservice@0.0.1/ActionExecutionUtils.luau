--!strict
--[=[
	Validates execution configuration and builds immutable cancellation tags.

	@util ActionExecutionUtils
]=]
const ActionExecutionStatuses = require("./ActionExecutionStatuses")
const ActionExecutionTypes = require("./ActionExecutionTypes")
const LockServiceUtils = require("@game/ReplicatedStorage/Packages/LockServiceUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

type ExecutionConfig = ActionExecutionTypes.ExecutionConfig
type Status = ActionExecutionTypes.Status

const isLockConfigShape = t.strictInterface({
	Key = t.string,
})

const isExecutionConfigShape = t.strictInterface({
	Actor = t.Instance,
	Tags = t.optional(t.array(t.string)),
	Timeout = t.number,
	Lock = t.optional(isLockConfigShape),
})

const ActionExecutionUtils = {}

--[=[
	Returns whether a value is a nonempty cancellation reason.

	@within ActionExecutionUtils
	@param value any
	@return boolean
]=]
function ActionExecutionUtils.isCancellationReason(value: any): boolean
	return t.string(value) and value ~= ""
end

--[=[
	Returns whether a value is a nonempty execution tag.

	@within ActionExecutionUtils
	@param value any
	@return boolean
]=]
function ActionExecutionUtils.isTag(value: any): boolean
	return t.string(value) and value ~= ""
end

--[=[
	Returns whether a value is a valid execution configuration.

	@within ActionExecutionUtils
	@param value any
	@return boolean
]=]
function ActionExecutionUtils.isExecutionConfig(value: any): boolean
	if not isExecutionConfigShape(value) or not LockServiceUtils.isTimeout(value.Timeout) then
		return false
	end
	if value.Lock and not LockServiceUtils.isLockKey(value.Lock.Key) then
		return false
	end

	const seenTags = {}
	for _, tag in value.Tags or {} do
		if not ActionExecutionUtils.isTag(tag) or seenTags[tag] then
			return false
		end
		seenTags[tag] = true
	end

	return true
end

--[=[
	Copies execution tags into a frozen constant-time lookup set.

	@within ActionExecutionUtils
	@param tags { string }?
	@return { [string]: true }
]=]
function ActionExecutionUtils.createTagSet(tags: { string }?): { [string]: true }
	assert(t.optional(t.array(t.string))(tags), "Bad tags")

	const tagSet: { [string]: true } = {}
	if tags then
		for _, tag in tags do
			assert(ActionExecutionUtils.isTag(tag), "Bad tags")
			assert(not tagSet[tag], "Duplicate tag")
			tagSet[tag] = true
		end
	end

	return table.freeze(tagSet)
end

--[=[
	Returns whether a value is a known execution status.

	@within ActionExecutionUtils
	@param value any
	@return boolean
]=]
function ActionExecutionUtils.isStatus(value: any): boolean
	return value == ActionExecutionStatuses.RUNNING
		or value == ActionExecutionStatuses.CANCELLING
		or value == ActionExecutionStatuses.SUCCEEDED
		or value == ActionExecutionStatuses.FAILED
		or value == ActionExecutionStatuses.CANCELLED
		or value == ActionExecutionStatuses.TIMED_OUT
end

--[=[
	Returns whether a status represents completed execution.

	@within ActionExecutionUtils
	@param status Status
	@return boolean
]=]
function ActionExecutionUtils.isTerminalStatus(status: Status): boolean
	assert(t.string(status) and ActionExecutionUtils.isStatus(status), "Bad status")
	return status == ActionExecutionStatuses.SUCCEEDED
		or status == ActionExecutionStatuses.FAILED
		or status == ActionExecutionStatuses.CANCELLED
		or status == ActionExecutionStatuses.TIMED_OUT
end

return ActionExecutionUtils
