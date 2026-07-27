--!strict
--[=[
	Implements a token-bucket rate limiter. Tokens refill continuously according
	to a monotonic clock and are consumed explicitly by callers.

	@class RateLimiter
]=]

const require = require("../Loader").load()

const BaseObject = require("BaseObject")
const Observable = require("Observable")
const ValueObject = require("ValueObject")
const t = require("t")

export type Clock = () -> number

const DEFAULT_CLOCK: Clock = os.clock

const RateLimiter = setmetatable({}, BaseObject)
RateLimiter.ClassName = "RateLimiter"
RateLimiter.__index = RateLimiter

export type RateLimiter =
	typeof(setmetatable(
		{} :: {
			_availableTokensValue: ValueObject.ValueObject<number>,
			_capacity: number,
			_clock: Clock,
			_destroyed: boolean,
			_lastRefillTime: number,
			_refillRate: number,
			_tokens: number,
		},
		{} :: typeof({ __index = RateLimiter })
	))
	& BaseObject.BaseObject<any>

function RateLimiter.new(capacity: number, refillRate: number, clock: Clock?): RateLimiter
	assert(t.number(capacity) and capacity > 0 and capacity < math.huge, "Bad capacity")
	assert(t.number(refillRate) and refillRate >= 0 and refillRate < math.huge, "Bad refillRate")
	assert(t.optional(t.callback)(clock), "Bad clock")

	const resolvedClock = clock or DEFAULT_CLOCK
	const currentTime = resolvedClock()

	assert(t.number(currentTime) and currentTime > -math.huge and currentTime < math.huge, "Clock returned bad time")

	const self = setmetatable(BaseObject.new() :: any, RateLimiter) :: RateLimiter

	self._availableTokensValue = self._maid:Add(ValueObject.new(capacity, "number"))
	self._capacity = capacity
	self._clock = resolvedClock
	self._destroyed = false
	self._lastRefillTime = currentTime
	self._refillRate = refillRate
	self._tokens = capacity
	self._maid:Add(function()
		self._destroyed = true
	end)

	return self
end

--[=[
	Returns the bucket's maximum token capacity.

	@within RateLimiter
	@return number
]=]
function RateLimiter.GetCapacity(self: RateLimiter): number
	return self._capacity
end

--[=[
	Returns the number of tokens restored per second.

	@within RateLimiter
	@return number
]=]
function RateLimiter.GetRefillRate(self: RateLimiter): number
	return self._refillRate
end

--[=[
	Returns the currently available tokens after applying elapsed refill time.

	@within RateLimiter
	@return number
]=]
function RateLimiter.GetAvailableTokens(self: RateLimiter): number
	self:_refill()
	return self._tokens
end

--[=[
	Attempts to consume tokens. Returns true on success and leaves the bucket
	unchanged when insufficient tokens are available.

	@within RateLimiter
	@param amount number?
	@return boolean
]=]
function RateLimiter.TryConsume(self: RateLimiter, amount: number?): boolean
	assert(t.optional(t.number)(amount), "Bad amount")

	const resolvedAmount = amount or 1
	assert(resolvedAmount > 0 and resolvedAmount < math.huge, "Bad amount")

	self:_refill()
	if self._tokens < resolvedAmount then
		return false
	end

	self:_setTokens(self._tokens - resolvedAmount)
	return true
end

--[=[
	Returns the seconds until the requested token amount will be available.
	Returns zero when it is already available and `math.huge` when the amount
	cannot be satisfied.

	@within RateLimiter
	@param amount number?
	@return number
]=]
function RateLimiter.GetRetryAfter(self: RateLimiter, amount: number?): number
	assert(t.optional(t.number)(amount), "Bad amount")

	const resolvedAmount = amount or 1
	assert(resolvedAmount > 0 and resolvedAmount < math.huge, "Bad amount")

	self:_refill()
	if self._tokens >= resolvedAmount then
		return 0
	end
	if resolvedAmount > self._capacity or self._refillRate == 0 then
		return math.huge
	end

	return (resolvedAmount - self._tokens) / self._refillRate
end

--[=[
	Adds tokens without exceeding the bucket capacity.

	@within RateLimiter
	@param amount number
]=]
function RateLimiter.AddTokens(self: RateLimiter, amount: number): ()
	assert(t.number(amount) and amount >= 0 and amount < math.huge, "Bad amount")

	self:_refill()
	self:_setTokens(self._tokens + amount)
end

--[=[
	Resets the bucket to a specific token count, or to full capacity when omitted.
	The refill clock restarts from the reset.

	@within RateLimiter
	@param tokens number?
]=]
function RateLimiter.Reset(self: RateLimiter, tokens: number?): ()
	assert(t.optional(t.number)(tokens), "Bad tokens")

	const resolvedTokens = tokens or self._capacity
	assert(resolvedTokens >= 0 and resolvedTokens <= self._capacity, "Bad tokens")

	self._lastRefillTime = self:_readClock()
	self:_setTokens(resolvedTokens)
end

--[=[
	Observes the last evaluated available-token count. The limiter evaluates and
	emits when it is queried or mutated; it does not allocate a per-frame timer.

	@within RateLimiter
	@return Observable<number>
]=]
function RateLimiter.ObserveAvailableTokens(self: RateLimiter): Observable.Observable<number>
	self:_refill()
	return self._availableTokensValue:Observe()
end

function RateLimiter._readClock(self: RateLimiter): number
	const currentTime = self._clock()
	assert(t.number(currentTime) and currentTime > -math.huge and currentTime < math.huge, "Clock returned bad time")

	return currentTime
end

function RateLimiter._refill(self: RateLimiter): ()
	const currentTime = self:_readClock()
	const elapsed = math.max(0, currentTime - self._lastRefillTime)
	self._lastRefillTime = math.max(self._lastRefillTime, currentTime)

	if elapsed == 0 or self._tokens >= self._capacity or self._refillRate == 0 then
		return
	end

	self:_setTokens(self._tokens + elapsed * self._refillRate)
end

function RateLimiter._setTokens(self: RateLimiter, tokens: number): ()
	self._tokens = math.clamp(tokens, 0, self._capacity)
	self._availableTokensValue.Value = self._tokens
end

return RateLimiter
