--!strict
--[=[
	A BasicPane transition driven by a linear `TimedTween`.

	@class TimedTransitionModel
]=]

const require = require("../Loader").load()

local BasicPane = require("BasicPane")
local Maid = require("Maid")
local Observable = require("Observable")
local Promise = require("Promise")
local TimedTween = require("TimedTween")
local TransitionModel = require("TransitionModel")
local ValueObject = require("ValueObject")

local TimedTransitionModel = setmetatable({}, BasicPane)
TimedTransitionModel.ClassName = "TimedTransitionModel"
TimedTransitionModel.__index = TimedTransitionModel

export type TimedTransitionModel =
	typeof(setmetatable(
		{} :: {
			_transitionModel: TransitionModel.TransitionModel,
			_timedTween: TimedTween.TimedTween,
		},
		{} :: typeof({ __index = TimedTransitionModel })
	))
	& BasicPane.BasicPane

--[=[
	Constructs a timed transition model.

	@within TimedTransitionModel
	@param transitionTime ValueObject.Mountable<number>?
	@return TimedTransitionModel
]=]
function TimedTransitionModel.new(transitionTime: ValueObject.Mountable<number>?): TimedTransitionModel
	local self: TimedTransitionModel = setmetatable(BasicPane.new() :: any, TimedTransitionModel)

	self._transitionModel = self._maid:Add(TransitionModel.new())
	self._transitionModel:BindToPaneVisbility(self)
	self._timedTween = self._maid:Add(TimedTween.new(transitionTime))

	self._transitionModel:SetPromiseShow(function(maid, doNotAnimate)
		return self:_promiseShow(maid, doNotAnimate)
	end)
	self._transitionModel:SetPromiseHide(function(maid, doNotAnimate)
		return self:_promiseHide(maid, doNotAnimate)
	end)

	return self
end

--[=[
	Sets or reactively mounts the full transition duration.

	@within TimedTransitionModel
	@param transitionTime ValueObject.Mountable<number>
	@return () -> ()
]=]
function TimedTransitionModel.SetTransitionTime(
	self: TimedTransitionModel,
	transitionTime: ValueObject.Mountable<number>
): () -> ()
	return self._timedTween:SetTransitionTime(transitionTime)
end

--[=[
	Returns whether showing has completed.

	@within TimedTransitionModel
	@return boolean
]=]
function TimedTransitionModel.IsShowingComplete(self: TimedTransitionModel): boolean
	return self._transitionModel:IsShowingComplete()
end

--[=[
	Returns whether hiding has completed.

	@within TimedTransitionModel
	@return boolean
]=]
function TimedTransitionModel.IsHidingComplete(self: TimedTransitionModel): boolean
	return self._transitionModel:IsHidingComplete()
end

--[=[
	Observes whether showing has completed.

	@within TimedTransitionModel
	@return Observable<boolean>
]=]
function TimedTransitionModel.ObserveIsShowingComplete(self: TimedTransitionModel): Observable.Observable<boolean>
	return self._transitionModel:ObserveIsShowingComplete()
end

--[=[
	Observes whether hiding has completed.

	@within TimedTransitionModel
	@return Observable<boolean>
]=]
function TimedTransitionModel.ObserveIsHidingComplete(self: TimedTransitionModel): Observable.Observable<boolean>
	return self._transitionModel:ObserveIsHidingComplete()
end

--[=[
	Mirrors visibility between this transition and another BasicPane.

	@within TimedTransitionModel
	@param pane BasicPane
	@return () -> ()
]=]
function TimedTransitionModel.BindToPaneVisbility(self: TimedTransitionModel, pane: BasicPane.BasicPane): () -> ()
	local maid = Maid.new()

	maid:GiveTask(pane.VisibleChanged:Connect(function(isVisible, doNotAnimate)
		self:SetVisible(isVisible, doNotAnimate)
	end))
	maid:GiveTask(self.VisibleChanged:Connect(function(isVisible, doNotAnimate)
		pane:SetVisible(isVisible, doNotAnimate)
	end))

	self:SetVisible(pane:IsVisible())
	self._maid._visibleBinding = maid

	return function()
		if self.Destroy and self._maid._visibleBinding == maid then
			self._maid._visibleBinding = nil
		end
	end
end

--[=[
	Observes the animated zero-to-one transition value on `RenderStepped`.

	@within TimedTransitionModel
	@return Observable<number>
]=]
function TimedTransitionModel.ObserveRenderStepped(self: TimedTransitionModel): Observable.Observable<number>
	return self._timedTween:ObserveRenderStepped()
end

--[=[
	Observes the animated zero-to-one transition value.

	@within TimedTransitionModel
	@return Observable<number>
]=]
function TimedTransitionModel.Observe(self: TimedTransitionModel): Observable.Observable<number>
	return self._timedTween:Observe()
end

--[=[
	Shows the model and resolves when the transition completes.

	@within TimedTransitionModel
	@param doNotAnimate boolean?
	@return Promise<()>
]=]
function TimedTransitionModel.PromiseShow(self: TimedTransitionModel, doNotAnimate: boolean?): Promise.Promise<()>
	return self._transitionModel:PromiseShow(doNotAnimate)
end

--[=[
	Hides the model and resolves when the transition completes.

	@within TimedTransitionModel
	@param doNotAnimate boolean?
	@return Promise<()>
]=]
function TimedTransitionModel.PromiseHide(self: TimedTransitionModel, doNotAnimate: boolean?): Promise.Promise<()>
	return self._transitionModel:PromiseHide(doNotAnimate)
end

--[=[
	Toggles the model and resolves when the transition completes.

	@within TimedTransitionModel
	@param doNotAnimate boolean?
	@return Promise<()>
]=]
function TimedTransitionModel.PromiseToggle(self: TimedTransitionModel, doNotAnimate: boolean?): Promise.Promise<()>
	return self._transitionModel:PromiseToggle(doNotAnimate)
end

function TimedTransitionModel._promiseShow(
	self: TimedTransitionModel,
	maid: Maid.Maid,
	doNotAnimate: boolean?
): Promise.Promise<()>
	self._timedTween:Show(doNotAnimate)

	if doNotAnimate then
		return Promise.resolved()
	end

	return maid:GivePromise(self._timedTween:PromiseFinished())
end

function TimedTransitionModel._promiseHide(
	self: TimedTransitionModel,
	maid: Maid.Maid,
	doNotAnimate: boolean?
): Promise.Promise<()>
	self._timedTween:Hide(doNotAnimate)

	if doNotAnimate then
		return Promise.resolved()
	end

	return maid:GivePromise(self._timedTween:PromiseFinished())
end

return TimedTransitionModel
