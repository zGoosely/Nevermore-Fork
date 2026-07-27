--!strict
--[=[
	Shared read-only behavior for one tagged cooldown Folder.

	@class CooldownBase
]=]

const require = require("../../Loader").load()

const BaseObject = require("BaseObject")
const CooldownServiceConstants = require("CooldownServiceConstants")
const CooldownServiceTypes = require("CooldownServiceTypes")
const CooldownServiceUtils = require("CooldownServiceUtils")
const Observable = require("Observable")
const Rx = require("Rx")
const RxAttributeUtils = require("RxAttributeUtils")
const Signal = require("Signal")
const t = require("t")

type Clock = CooldownServiceTypes.Clock
type CooldownState = CooldownServiceTypes.CooldownState

const CooldownBase = setmetatable({}, BaseObject)
CooldownBase.ClassName = "CooldownBase"
CooldownBase.__index = CooldownBase

export type CooldownBase =
	typeof(setmetatable(
		{} :: {
			_obj: Folder,
			_clock: Clock,
			Changed: Signal.Signal<()>,
		},
		{} :: typeof({ __index = CooldownBase })
	))
	& BaseObject.BaseObject<Folder>

function CooldownBase.new(folder: Folder, clock: Clock): CooldownBase
	assert(t.instanceIsA("Folder")(folder), "Bad folder")
	assert(t.callback(clock), "Bad clock")

	const self = setmetatable(BaseObject.new(folder) :: any, CooldownBase) :: CooldownBase
	self._clock = clock
	self.Changed = self._maid:Add(Signal.new())

	self._maid:Add(folder:GetPropertyChangedSignal("Parent"):Connect(function()
		self.Changed:Fire()
	end))
	self._maid:Add(folder:GetAttributeChangedSignal(CooldownServiceConstants.KEY_ATTRIBUTE):Connect(function()
		self.Changed:Fire()
	end))
	self._maid:Add(folder:GetAttributeChangedSignal(CooldownServiceConstants.STARTED_AT_ATTRIBUTE):Connect(function()
		self.Changed:Fire()
	end))
	self._maid:Add(folder:GetAttributeChangedSignal(CooldownServiceConstants.ENDS_AT_ATTRIBUTE):Connect(function()
		self.Changed:Fire()
	end))
	self._maid:Add(folder:GetAttributeChangedSignal(CooldownServiceConstants.PREDICTED_ATTRIBUTE):Connect(function()
		self.Changed:Fire()
	end))

	return self
end

--[=[
	Returns the tagged Folder carrying this cooldown.

	@within CooldownBase
	@return Folder
]=]
function CooldownBase.GetFolder(self: CooldownBase): Folder
	return self._obj
end

--[=[
	Returns the complete validated state, or nil while the Folder is malformed or
	unparented.

	@within CooldownBase
	@return CooldownState?
]=]
function CooldownBase.GetState(self: CooldownBase): CooldownState?
	return CooldownServiceUtils.readState(self._obj)
end

--[=[
	Returns the Instance that owns this cooldown, or nil while unparented.

	@within CooldownBase
	@return Instance?
]=]
function CooldownBase.GetOwner(self: CooldownBase): Instance?
	const state = self:GetState()
	return if state then state.Owner else self._obj.Parent
end

--[=[
	Returns this cooldown's case-sensitive lookup key.

	@within CooldownBase
	@return string
]=]
function CooldownBase.GetKey(self: CooldownBase): string
	const state = self:GetState()
	return assert(state, "Cooldown Folder has invalid state").Key
end

--[=[
	Returns the synchronized timestamp at which this cooldown began.

	@within CooldownBase
	@return number
]=]
function CooldownBase.GetStartedAt(self: CooldownBase): number
	const state = self:GetState()
	return assert(state, "Cooldown Folder has invalid state").StartedAt
end

--[=[
	Returns the synchronized timestamp at which this cooldown ends.

	@within CooldownBase
	@return number
]=]
function CooldownBase.GetEndsAt(self: CooldownBase): number
	const state = self:GetState()
	return assert(state, "Cooldown Folder has invalid state").EndsAt
end

--[=[
	Returns the configured duration between the start and end timestamps.

	@within CooldownBase
	@return number
]=]
function CooldownBase.GetDuration(self: CooldownBase): number
	const state = self:GetState()
	return assert(state, "Cooldown Folder has invalid state").EndsAt - state.StartedAt
end

--[=[
	Returns the current nonnegative remaining duration.

	@within CooldownBase
	@return number
]=]
function CooldownBase.GetRemainingTime(self: CooldownBase): number
	const state = self:GetState()
	if not state then
		return 0
	end

	return math.max(0, state.EndsAt - self:_readClock())
end

--[=[
	Returns whether this cooldown has valid state and has not expired.

	@within CooldownBase
	@return boolean
]=]
function CooldownBase.IsActive(self: CooldownBase): boolean
	const state = self:GetState()
	return state ~= nil and state.EndsAt > self:_readClock()
end

--[=[
	Returns whether this is a local client prediction.

	@within CooldownBase
	@return boolean
]=]
function CooldownBase.IsPredicted(self: CooldownBase): boolean
	const state = self:GetState()
	return state ~= nil and state.IsPredicted
end

--[=[
	Observes validated end timestamps. Malformed values are represented by nil.

	@within CooldownBase
	@return Observable<number?>
]=]
function CooldownBase.ObserveEndsAt(self: CooldownBase): Observable.Observable<number?>
	return RxAttributeUtils.observeAttribute(self._obj, CooldownServiceConstants.ENDS_AT_ATTRIBUTE):Pipe({
		Rx.map(function(value): number?
			return if CooldownServiceUtils.isFiniteNumber(value) then value else nil
		end),
		Rx.distinct() :: any,
	}) :: any
end

--[=[
	Observes complete state snapshots whenever relevant attributes or ownership
	change.

	@within CooldownBase
	@return Observable<CooldownState?>
]=]
function CooldownBase.ObserveState(self: CooldownBase): Observable.Observable<CooldownState?>
	return Observable.new(function(sub)
		sub:Fire(self:GetState())
		return self.Changed:Connect(function()
			sub:Fire(self:GetState())
		end)
	end)
end

function CooldownBase._readClock(self: CooldownBase): number
	const currentTime = self._clock()
	assert(CooldownServiceUtils.isFiniteNumber(currentTime), "Clock returned bad time")
	return currentTime
end

return CooldownBase
