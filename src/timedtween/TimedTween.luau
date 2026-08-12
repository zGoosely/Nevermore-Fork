--!strict
--[=[
	A zero-to-one linear tween with a configurable transition time.

	@class TimedTween
]=]

local RunService = game:GetService("RunService")

const require = require("../Loader").load()

local BasicPane = require("BasicPane")
local Maid = require("Maid")
local MathUtils = require("MathUtils")
local Observable = require("Observable")
local Promise = require("Promise")
local StepUtils = require("StepUtils")
local ValueObject = require("ValueObject")

type TimedTweenState = {
	p0: number,
	p1: number,
	t0: number,
	t1: number,
}

type ComputedState = {
	p: number,
	v: number,
	rtime: number,
}

local TimedTween = setmetatable({}, BasicPane)
TimedTween.ClassName = "TimedTween"
TimedTween.__index = TimedTween

export type TimedTween =
	typeof(setmetatable(
		{} :: {
			_state: ValueObject.ValueObject<TimedTweenState>,
			_transitionTime: ValueObject.ValueObject<number>,
		},
		{} :: typeof({ __index = TimedTween })
	))
	& BasicPane.BasicPane

--[=[
	Constructs a timed tween. The default transition time is `0.15` seconds.

	@within TimedTween
	@param transitionTime ValueObject.Mountable<number>?
	@return TimedTween
]=]
function TimedTween.new(transitionTime: ValueObject.Mountable<number>?): TimedTween
	local self: TimedTween = setmetatable(BasicPane.new() :: any, TimedTween)

	self._transitionTime = self._maid:Add(ValueObject.new(0.15, "number"))
	self._state = self._maid:Add(ValueObject.new({
		p0 = 0,
		p1 = 0,
		t0 = 0,
		t1 = 0,
	}))

	if transitionTime then
		self:SetTransitionTime(transitionTime)
	end

	self._maid:GiveTask(self._transitionTime.Changed:Connect(function()
		self:_updateState()
	end))
	self._maid:GiveTask(self.VisibleChanged:Connect(function(_, doNotAnimate)
		self:_updateState(doNotAnimate)
	end))

	self:_updateState()

	return self
end

--[=[
	Sets or reactively mounts the full transition duration.

	@within TimedTween
	@param transitionTime ValueObject.Mountable<number>
	@return () -> ()
]=]
function TimedTween.SetTransitionTime(self: TimedTween, transitionTime: ValueObject.Mountable<number>): () -> ()
	return self._transitionTime:Mount(transitionTime)
end

--[=[
	Returns the current full transition duration.

	@within TimedTween
	@return number
]=]
function TimedTween.GetTransitionTime(self: TimedTween): number
	return self._transitionTime.Value
end

--[=[
	Observes the configured transition duration.

	@within TimedTween
	@return Observable<number>
]=]
function TimedTween.ObserveTransitionTime(self: TimedTween): Observable.Observable<number>
	return self._transitionTime:Observe()
end

--[=[
	Observes the tween value on `RenderStepped` while it is moving.

	@within TimedTween
	@return Observable<number>
]=]
function TimedTween.ObserveRenderStepped(self: TimedTween): Observable.Observable<number>
	return self:ObserveOnSignal(RunService.RenderStepped)
end

--[=[
	Observes the tween on a specific engine signal.

	@within TimedTween
	@param signal RBXScriptSignal
	@return Observable<number>
]=]
function TimedTween.ObserveOnSignal(self: TimedTween, signal: RBXScriptSignal): Observable.Observable<number>
	return Observable.new(function(sub)
		local maid = Maid.new()
		local startAnimation, stopAnimation = StepUtils.bindToSignal(signal, function()
			local state = self:_computeState(os.clock())
			sub:Fire(state.p)
			return state.rtime > 0
		end)

		maid:GiveTask(stopAnimation)
		maid:GiveTask(self._state.Changed:Connect(startAnimation))
		startAnimation()

		return maid
	end) :: any
end

--[=[
	Observes the tween value. This aliases `ObserveRenderStepped()`.

	@within TimedTween
	@return Observable<number>
]=]
function TimedTween.Observe(self: TimedTween): Observable.Observable<number>
	return self:ObserveRenderStepped()
end

--[=[
	Resolves when the current transition reaches its target.

	@within TimedTween
	@return Promise<()>
]=]
function TimedTween.PromiseFinished(self: TimedTween): Promise.Promise<()>
	local initialState = self:_computeState(os.clock())
	if initialState.rtime <= 0 then
		return Promise.resolved()
	end

	local maid = Maid.new()
	local promise = Promise.new()
	maid:GiveTask(promise)

	maid:GiveTask(self._state:Observe():Subscribe(function()
		local state = self:_computeState(os.clock())
		if state.rtime <= 0 then
			promise:Resolve()
			return
		end

		maid._scheduled = task.delay(state.rtime, function()
			promise:Resolve()
		end)
	end))

	self._maid[promise] = maid
	promise:Finally(function()
		self._maid[promise] = nil
	end)

	maid:GiveTask(function()
		self._maid[promise] = nil
	end)

	return promise
end

function TimedTween._updateState(self: TimedTween, doNotAnimate: boolean?): ()
	local transitionTime = math.max(0, self._transitionTime.Value)
	local target = if self:IsVisible() then 1 else 0
	local now = os.clock()
	local position = self:_computeState(now).p

	if doNotAnimate then
		self._state.Value = {
			p0 = target,
			p1 = target,
			t0 = now,
			t1 = now,
		}
	else
		self._state.Value = {
			p0 = position,
			p1 = target,
			t0 = now,
			t1 = now + MathUtils.map(math.abs(target - position), 0, 1, 0, transitionTime),
		}
	end
end

function TimedTween._computeState(self: TimedTween, now: number): ComputedState
	local state = self._state.Value
	local duration = math.max(0, state.t1 - state.t0)
	local position

	if duration == 0 then
		position = state.p1
	else
		position = MathUtils.map(math.clamp(now, state.t0, state.t1), state.t0, state.t1, state.p0, state.p1)
	end

	local remainingTime = math.abs(state.p1 - position) * duration
	local velocity = if remainingTime > 0 and duration > 0 then (state.p1 - state.p0) / duration else 0

	return {
		p = position,
		v = velocity,
		rtime = remainingTime,
	}
end

return TimedTween
