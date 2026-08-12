--!strict
--[=[
	Owns one cancellable server operation and its optional lock permit.

	@class ActionExecution
	@server
]=]

const require = require("../Loader").load()

const ActionExecutionStatuses = require("ActionExecutionStatuses")
const ActionExecutionTypes = require("ActionExecutionTypes")
const ActionExecutionUtils = require("ActionExecutionUtils")
const CancelTokenSource = require("CancelTokenSource")
const LockPermit = require("LockPermit")
const Maid = require("Maid")
const Observable = require("Observable")
const Promise = require("Promise")
const ValueObject = require("ValueObject")
const t = require("t")

type ExecutionCallback = ActionExecutionTypes.ExecutionCallback
type ExecutionConfig = ActionExecutionTypes.ExecutionConfig
type Status = ActionExecutionTypes.Status

export type CompletionCallback = () -> ()

const DEFAULT_CANCEL_REASON = "Cancelled"
const DESTROYED_REASON = "ExecutionDestroyed"
const TIMEOUT_REASON = "Timeout"

const ActionExecution = {}
ActionExecution.ClassName = "ActionExecution"
ActionExecution.__index = ActionExecution

export type ActionExecution = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_activeMaid: Maid.Maid,
		_actor: Instance,
		_tags: { [string]: true },
		_lockPermit: LockPermit.LockPermit?,
		_cancelTokenSource: CancelTokenSource.CancelTokenSource,
		_statusValue: ValueObject.ValueObject<Status>,
		_resultPromise: Promise.Promise<any>,
		_completionCallback: CompletionCallback,
		_timeoutThread: thread?,
		_cancelReason: string?,
		_isTimingOut: boolean,
		_isFinalized: boolean,
		_destroyed: boolean,
	},
	{} :: typeof({ __index = ActionExecution })
))

function ActionExecution.new(
	config: ExecutionConfig,
	lockPermit: LockPermit.LockPermit?,
	callback: ExecutionCallback,
	completionCallback: CompletionCallback
): ActionExecution
	assert(ActionExecutionUtils.isExecutionConfig(config), "Bad config")
	assert(t.optional(t.table)(lockPermit), "Bad lockPermit")
	assert(t.callback(callback), "Bad callback")
	assert(t.callback(completionCallback), "Bad completionCallback")
	assert((config.Lock == nil) == (lockPermit == nil), "Lock config and permit must match")
	if config.Lock and lockPermit then
		assert(lockPermit:GetOwner() == config.Actor, "Lock permit has the wrong actor")
		assert(lockPermit:GetKey() == config.Lock.Key, "Lock permit has the wrong key")
		assert(lockPermit:GetHolder() == config.Actor, "Lock permit has the wrong holder")
	end

	const self = setmetatable({}, ActionExecution) :: ActionExecution
	self._maid = Maid.new()
	self._activeMaid = Maid.new()
	self._actor = config.Actor
	self._tags = ActionExecutionUtils.createTagSet(config.Tags)
	self._lockPermit = lockPermit
	self._cancelTokenSource = CancelTokenSource.new()
	self._statusValue =
		self._maid:Add(ValueObject.new(ActionExecutionStatuses.RUNNING :: Status, ActionExecutionUtils.isStatus))
	self._resultPromise = Promise.new()
	self._completionCallback = completionCallback
	self._timeoutThread = nil
	self._cancelReason = nil
	self._isTimingOut = false
	self._isFinalized = false
	self._destroyed = false

	self._resultPromise:Catch(function() end)
	self._activeMaid:Add(config.Actor.Destroying:Connect(function()
		self:Cancel("ActorDestroyed")
	end))
	if lockPermit then
		self._activeMaid._lockReleased = lockPermit.Released:Connect(function(reason)
			self:_handleExternalLockRelease(reason)
		end)
	end
	self._timeoutThread = task.delay(config.Timeout, function()
		self:_timeOut()
	end)

	task.defer(function()
		if not self._isFinalized then
			self:_invoke(callback)
		end
	end)

	return self
end

--[=[
	Returns the Instance performing this action.

	@within ActionExecution
	@return Instance
]=]
function ActionExecution.GetActor(self: ActionExecution): Instance
	return self._actor
end

--[=[
	Returns whether this execution was started with a tag.

	@within ActionExecution
	@param tag string
	@return boolean
]=]
function ActionExecution.HasTag(self: ActionExecution, tag: string): boolean
	assert(ActionExecutionUtils.isTag(tag), "Bad tag")
	return self._tags[tag] == true
end

--[=[
	Returns the current execution status.

	@within ActionExecution
	@return Status
]=]
function ActionExecution.GetStatus(self: ActionExecution): Status
	return self._statusValue.Value
end

--[=[
	Observes status transitions for this execution.

	@within ActionExecution
	@return Observable<Status>
]=]
function ActionExecution.ObserveStatus(self: ActionExecution): Observable.Observable<Status>
	return self._statusValue:Observe()
end

--[=[
	Returns whether the callback is running or cooperatively cancelling.

	@within ActionExecution
	@return boolean
]=]
function ActionExecution.IsActive(self: ActionExecution): boolean
	return not self._isFinalized
end

--[=[
	Returns the first cancellation reason, or nil when cancellation was not
	requested.

	@within ActionExecution
	@return string?
]=]
function ActionExecution.GetCancelReason(self: ActionExecution): string?
	return self._cancelReason
end

--[=[
	Returns the Promise that resolves on success and rejects on failure,
	cancellation, or timeout.

	@within ActionExecution
	@return Promise
]=]
function ActionExecution.GetPromise(self: ActionExecution): Promise.Promise<any>
	return self._resultPromise
end

--[=[
	Requests cooperative cancellation. The lock remains held until the callback
	settles or the required timeout expires.

	@within ActionExecution
	@param reason string?
	@return boolean
]=]
function ActionExecution.Cancel(self: ActionExecution, reason: string?): boolean
	assert(t.optional(t.string)(reason), "Bad reason")
	assert(reason == nil or ActionExecutionUtils.isCancellationReason(reason), "Bad reason")

	if self._isFinalized or self._statusValue.Value == ActionExecutionStatuses.CANCELLING then
		return false
	end

	self._cancelReason = reason or DEFAULT_CANCEL_REASON
	self._statusValue.Value = ActionExecutionStatuses.CANCELLING :: Status
	self._cancelTokenSource:Cancel(self._cancelReason)
	return true
end

function ActionExecution._invoke(self: ActionExecution, callback: ExecutionCallback): ()
	const succeeded, callbackResult = pcall(callback, self._cancelTokenSource:GetToken())
	if not succeeded then
		self:_reject(callbackResult)
		return
	end
	if not (t.table(callbackResult) and Promise.isPromise(callbackResult)) then
		self:_reject("ActionExecution callback must return a Promise")
		return
	end

	const callbackPromise = callbackResult :: Promise.Promise<any>
	callbackPromise:Then(function(...)
		self:_resolve(...)
	end, function(...)
		self:_reject(...)
	end)
end

function ActionExecution._resolve(self: ActionExecution, ...: any): ()
	if self._isFinalized or self._isTimingOut then
		return
	end
	if self._cancelTokenSource:IsCancelled() then
		self:_finalize(ActionExecutionStatuses.CANCELLED :: Status, false, self._cancelReason or DEFAULT_CANCEL_REASON)
		return
	end

	self:_finalize(ActionExecutionStatuses.SUCCEEDED :: Status, true, ...)
end

function ActionExecution._reject(self: ActionExecution, ...: any): ()
	if self._isFinalized or self._isTimingOut then
		return
	end
	if self._cancelTokenSource:IsCancelled() then
		self:_finalize(ActionExecutionStatuses.CANCELLED :: Status, false, self._cancelReason or DEFAULT_CANCEL_REASON)
		return
	end

	self:_finalize(ActionExecutionStatuses.FAILED :: Status, false, ...)
end

function ActionExecution._timeOut(self: ActionExecution): ()
	if self._isFinalized then
		return
	end

	self._cancelReason = TIMEOUT_REASON
	self._isTimingOut = true
	self._cancelTokenSource:Cancel(TIMEOUT_REASON)
	self:_finalize(ActionExecutionStatuses.TIMED_OUT :: Status, false, TIMEOUT_REASON)
end

function ActionExecution._handleExternalLockRelease(self: ActionExecution, reason: string): ()
	if self._isFinalized then
		return
	end
	if reason == TIMEOUT_REASON then
		self:_timeOut()
		return
	end

	self._cancelReason = reason
	self._cancelTokenSource:Cancel(reason)
	self:_finalize(ActionExecutionStatuses.CANCELLED :: Status, false, reason)
end

function ActionExecution._finalize(self: ActionExecution, status: Status, shouldResolve: boolean, ...: any): ()
	assert(ActionExecutionUtils.isTerminalStatus(status), "Bad terminal status")
	if self._isFinalized then
		return
	end
	self._isFinalized = true
	self._statusValue.Value = status

	self._activeMaid._lockReleased = nil
	self._activeMaid:DoCleaning()

	const timeoutThread = self._timeoutThread
	self._timeoutThread = nil
	if timeoutThread and timeoutThread ~= coroutine.running() then
		task.cancel(timeoutThread)
	end

	const lockPermit = self._lockPermit
	if lockPermit and not lockPermit:IsReleased() then
		lockPermit:Release(if status == ActionExecutionStatuses.TIMED_OUT then TIMEOUT_REASON else status)
	end

	self._completionCallback()
	if shouldResolve then
		self._resultPromise:Resolve(...)
	else
		self._resultPromise:Reject(...)
	end
end

function ActionExecution.Destroy(self: ActionExecution): ()
	if self._destroyed then
		return
	end
	self._destroyed = true

	if not self._isFinalized then
		self._cancelReason = DESTROYED_REASON
		self._cancelTokenSource:Cancel(DESTROYED_REASON)
		self:_finalize(ActionExecutionStatuses.CANCELLED :: Status, false, DESTROYED_REASON)
	end

	self._cancelTokenSource:Destroy()
	self._activeMaid:DoCleaning()
	self._maid:DoCleaning()
end

return ActionExecution
