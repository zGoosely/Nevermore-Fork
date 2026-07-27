--!strict
--[=[
	Limits the number of asynchronous operations running concurrently. Waiting
	callers receive permits in FIFO order.

	@class AsyncSemaphore
]=]

const require = require("../Loader").load()

const AsyncSemaphorePermit = require("AsyncSemaphorePermit")
const BaseObject = require("BaseObject")
const Observable = require("Observable")
const Promise = require("Promise")
const Queue = require("Queue")
const ValueObject = require("ValueObject")
const t = require("t")

const DESTROYED_ERROR = "AsyncSemaphore is destroyed"

export type Permit = AsyncSemaphorePermit.AsyncSemaphorePermit

type Waiter = {
	isQueued: boolean,
	promise: Promise.Promise<Permit>,
}

const AsyncSemaphore = setmetatable({}, BaseObject)
AsyncSemaphore.ClassName = "AsyncSemaphore"
AsyncSemaphore.__index = AsyncSemaphore

export type AsyncSemaphore =
	typeof(setmetatable(
		{} :: {
			_activeCount: number,
			_activeCountValue: ValueObject.ValueObject<number>,
			_availableCountValue: ValueObject.ValueObject<number>,
			_destroyed: boolean,
			_maxConcurrency: number,
			_queue: Queue.Queue<Waiter>,
			_waitingCount: number,
		},
		{} :: typeof({ __index = AsyncSemaphore })
	))
	& BaseObject.BaseObject<any>

function AsyncSemaphore.new(maxConcurrency: number): AsyncSemaphore
	assert(t.number(maxConcurrency) and maxConcurrency >= 1 and maxConcurrency % 1 == 0, "Bad maxConcurrency")

	const self = setmetatable(BaseObject.new() :: any, AsyncSemaphore) :: AsyncSemaphore

	self._activeCount = 0
	self._activeCountValue = self._maid:Add(ValueObject.new(0, "number"))
	self._availableCountValue = self._maid:Add(ValueObject.new(maxConcurrency, "number"))
	self._destroyed = false
	self._maxConcurrency = maxConcurrency
	self._queue = Queue.new()
	self._waitingCount = 0
	self._maid:Add(function()
		self:_cleanup()
	end)

	return self
end

--[=[
	Returns the maximum number of concurrent permits.

	@within AsyncSemaphore
	@return number
]=]
function AsyncSemaphore.GetMaxConcurrency(self: AsyncSemaphore): number
	return self._maxConcurrency
end

--[=[
	Changes the maximum concurrency. Reducing the limit does not revoke active
	permits; queued callers resume once enough active permits are released.

	@within AsyncSemaphore
	@param maxConcurrency number
]=]
function AsyncSemaphore.SetMaxConcurrency(self: AsyncSemaphore, maxConcurrency: number): ()
	assert(t.number(maxConcurrency) and maxConcurrency >= 1 and maxConcurrency % 1 == 0, "Bad maxConcurrency")
	assert(not self._destroyed, DESTROYED_ERROR)

	self._maxConcurrency = maxConcurrency
	self:_updateCountValues()
	self:_drainQueue()
end

--[=[
	Returns the number of currently active permits.

	@within AsyncSemaphore
	@return number
]=]
function AsyncSemaphore.GetActiveCount(self: AsyncSemaphore): number
	return self._activeCount
end

--[=[
	Returns the number of permits immediately available.

	@within AsyncSemaphore
	@return number
]=]
function AsyncSemaphore.GetAvailableCount(self: AsyncSemaphore): number
	return math.max(0, self._maxConcurrency - self._activeCount)
end

--[=[
	Returns the number of callers waiting for a permit.

	@within AsyncSemaphore
	@return number
]=]
function AsyncSemaphore.GetWaitingCount(self: AsyncSemaphore): number
	return self._waitingCount
end

--[=[
	Attempts to acquire a permit synchronously. Returns an idempotent release
	object when successful, or nil when every permit is occupied.

	@within AsyncSemaphore
	@return AsyncSemaphorePermit?
]=]
function AsyncSemaphore.TryAcquire(self: AsyncSemaphore): Permit?
	assert(not self._destroyed, DESTROYED_ERROR)

	if self._activeCount >= self._maxConcurrency then
		return nil
	end

	return self:_takePermit()
end

--[=[
	Promises an idempotent permit once one becomes available.
	Queued callers are resumed in FIFO order.

	@within AsyncSemaphore
	@return Promise<AsyncSemaphorePermit>
]=]
function AsyncSemaphore.AcquireAsync(self: AsyncSemaphore): Promise.Promise<Permit>
	if self._destroyed then
		return Promise.rejected(DESTROYED_ERROR)
	end

	const permit = self:TryAcquire()
	if permit ~= nil then
		return Promise.resolved(permit)
	end

	const promise: Promise.Promise<Permit> = Promise.new()
	const waiter: Waiter = {
		isQueued = true,
		promise = promise,
	}

	self._queue:PushRight(waiter)
	self._waitingCount += 1

	-- Promise:Destroy() rejects a pending acquisition. Mark it cancelled here;
	-- the queue discards the lightweight entry when it reaches the front.
	promise:Catch(function()
		if waiter.isQueued then
			waiter.isQueued = false
			self._waitingCount -= 1
			self:_drainQueue()
		end
	end)

	return promise
end

--[=[
	Acquires a permit, invokes a promise-returning callback, and releases the
	permit after that promise resolves or rejects.

	@within AsyncSemaphore
	@param callback () -> Promise<T...>
	@return Promise<T...>
]=]
function AsyncSemaphore.RunAsync<T...>(self: AsyncSemaphore, callback: () -> Promise.Promise<T...>): Promise.Promise<T...>
	assert(t.callback(callback), "Bad callback")

	return self:AcquireAsync():Then(function(permit: Permit)
		const succeeded, callbackResult = pcall(callback)
		if not succeeded then
			permit:Release()
			return Promise.rejected(callbackResult)
		end

		if not (t.table(callbackResult) and Promise.isPromise(callbackResult)) then
			permit:Release()
			return Promise.rejected("AsyncSemaphore callback must return a Promise")
		end

		return (callbackResult :: Promise.Promise<T...>):Then(function(...: T...)
			permit:Release()
			return Promise.resolved(...)
		end, function(...)
			permit:Release()
			return Promise.rejected(...)
		end)
	end) :: any
end

--[=[
	Observes the current active permit count.

	@within AsyncSemaphore
	@return Observable<number>
]=]
function AsyncSemaphore.ObserveActiveCount(self: AsyncSemaphore): Observable.Observable<number>
	return self._activeCountValue:Observe()
end

--[=[
	Observes the number of permits immediately available.

	@within AsyncSemaphore
	@return Observable<number>
]=]
function AsyncSemaphore.ObserveAvailableCount(self: AsyncSemaphore): Observable.Observable<number>
	return self._availableCountValue:Observe()
end

function AsyncSemaphore._takePermit(self: AsyncSemaphore): Permit
	self._activeCount += 1
	self:_updateCountValues()

	return AsyncSemaphorePermit.new(function()
		if self._destroyed then
			return
		end

		assert(self._activeCount > 0, "AsyncSemaphore permit count underflow")
		self._activeCount -= 1
		self:_updateCountValues()
		self:_drainQueue()
	end)
end

function AsyncSemaphore._drainQueue(self: AsyncSemaphore): ()
	if self._destroyed then
		return
	end

	while self._activeCount < self._maxConcurrency and not self._queue:IsEmpty() do
		const waiter = self._queue:PopLeft()
		if not waiter.isQueued then
			continue
		end

		waiter.isQueued = false
		self._waitingCount -= 1

		if waiter.promise:IsPending() then
			waiter.promise:Resolve(self:_takePermit())
		end
	end
end

function AsyncSemaphore._updateCountValues(self: AsyncSemaphore): ()
	self._activeCountValue.Value = self._activeCount
	self._availableCountValue.Value = math.max(0, self._maxConcurrency - self._activeCount)
end

function AsyncSemaphore._cleanup(self: AsyncSemaphore): ()
	if self._destroyed then
		return
	end
	self._destroyed = true

	while not self._queue:IsEmpty() do
		const waiter = self._queue:PopLeft()
		if waiter.isQueued then
			waiter.isQueued = false
			self._waitingCount -= 1
			waiter.promise:Reject(DESTROYED_ERROR)
		end
	end
end

return AsyncSemaphore
