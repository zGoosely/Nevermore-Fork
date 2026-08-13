--!strict
--[=[
	Provides a read-only signal for cooperative cancellation. Cancellation
	authority belongs to the executor or a [CancelTokenSource].

	@class CancelToken
]=]
const DuckTypeUtils = require("@game/ReplicatedStorage/Packages/DuckTypeUtils")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const Signal = require("@game/ReplicatedStorage/Packages/Signal")
const t = require("@game/ReplicatedStorage/Packages/t")

const DEFAULT_REASON = "Cancelled"
const MAID_REASON = "MaidCleaned"
const TIMEOUT_REASON = "Timeout"

export type Cancel = (reason: string?) -> ()
export type Executor = (cancel: Cancel, maid: Maid.Maid) -> ()

const CancelToken = {}
CancelToken.ClassName = "CancelToken"
CancelToken.__index = CancelToken

export type CancelToken = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_isCancelled: boolean,
		_reason: string?,
		Cancelled: Signal.Signal<()>,
		PromiseCancelled: Promise.Promise<()>,
	},
	{} :: typeof({ __index = CancelToken })
))

function CancelToken.new(executor: Executor): CancelToken
	assert(t.callback(executor), "Bad executor")

	const self = setmetatable({}, CancelToken) :: CancelToken
	self._maid = Maid.new()
	self._isCancelled = false
	self._reason = nil
	self.Cancelled = Signal.new()
	self.PromiseCancelled = Promise.new()
	self._maid:Add(function()
		if not self._isCancelled then
			self._isCancelled = true
			self._reason = MAID_REASON
			self.PromiseCancelled:Resolve()
			self.Cancelled:Fire()
		end
		self.Cancelled:Destroy()
	end)

	executor(function(reason)
		self:_cancel(reason)
	end, self._maid)

	return self
end

--[=[
	Returns whether a value implements the cancellation-token contract.

	@within CancelToken
	@param value any
	@return boolean
]=]
function CancelToken.isCancelToken(value: any): boolean
	return DuckTypeUtils.isImplementation(CancelToken, value)
end

--[=[
	Creates a token that cancels when the given Maid is cleaned.

	@within CancelToken
	@param maid Maid
	@return CancelToken
]=]
function CancelToken.fromMaid(maid: Maid.Maid): CancelToken
	assert(t.table(maid) and Maid.isMaid(maid), "Bad maid")

	const token = CancelToken.new(function() end)
	const taskId = maid:Add(function()
		token:_cancel(MAID_REASON)
	end)

	token.PromiseCancelled:Then(function()
		maid[taskId] = nil
	end)

	return token
end

--[=[
	Creates a token that cancels after the given number of seconds.

	@within CancelToken
	@param seconds number
	@return CancelToken
]=]
function CancelToken.fromSeconds(seconds: number): CancelToken
	assert(t.number(seconds) and seconds >= 0 and seconds < math.huge, "Bad seconds")

	return CancelToken.new(function(cancel, maid)
		maid:Add(task.delay(seconds, function()
			cancel(TIMEOUT_REASON)
		end))
	end)
end

--[=[
	Raises an error containing the cancellation reason when cancelled.

	@within CancelToken
]=]
function CancelToken.ErrorIfCancelled(self: CancelToken): ()
	if self._isCancelled then
		error(`[CancelToken.ErrorIfCancelled] - {self._reason or DEFAULT_REASON}`, 2)
	end
end

--[=[
	Returns whether cancellation has been requested.

	@within CancelToken
	@return boolean
]=]
function CancelToken.IsCancelled(self: CancelToken): boolean
	return self._isCancelled
end

--[=[
	Returns the first cancellation reason, or nil while active.

	@within CancelToken
	@return string?
]=]
function CancelToken.GetReason(self: CancelToken): string?
	return self._reason
end

function CancelToken._cancel(self: CancelToken, reason: string?): ()
	assert(t.optional(t.string)(reason), "Bad reason")
	assert(reason == nil or reason ~= "", "Bad reason")

	if self._isCancelled then
		return
	end

	self._isCancelled = true
	self._reason = reason or DEFAULT_REASON
	self.PromiseCancelled:Resolve()
	self.Cancelled:Fire()
	self._maid:DoCleaning()
end

return CancelToken
