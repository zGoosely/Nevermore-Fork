--!strict
--[=[
	Maintains constant-time owner/key cooldown lookup and reactive selection over
	all models produced by one realm's Cooldown binder.

	@class CooldownRegistry
]=]
const Binder = require("@game/ReplicatedStorage/Packages/Binder")
const CooldownExpiryScheduler = require("./CooldownExpiryScheduler")
const CooldownServiceTypes = require("./CooldownServiceTypes")
const CooldownServiceUtils = require("./CooldownServiceUtils")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const Signal = require("@game/ReplicatedStorage/Packages/Signal")
const t = require("@game/ReplicatedStorage/Packages/t")

type Clock = CooldownServiceTypes.Clock
type CooldownModel = CooldownServiceTypes.CooldownModel
type CooldownState = CooldownServiceTypes.CooldownState

type Slot = {
	Owner: Instance,
	Key: string,
	Candidates: { [CooldownModel]: number },
	Selected: CooldownModel?,
	Changed: Signal.Signal<CooldownModel?>,
	ObserverCount: number,
}

type ModelEntry = {
	Maid: Maid.Maid,
	Slot: Slot?,
	IsExpired: boolean,
}

const CooldownRegistry = {}
CooldownRegistry.ClassName = "CooldownRegistry"
CooldownRegistry.__index = CooldownRegistry

export type CooldownRegistry = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_binder: Binder.Binder<CooldownModel>,
		_clock: Clock,
		_scheduler: CooldownExpiryScheduler.CooldownExpiryScheduler,
		_slotsByOwner: { [Instance]: { [string]: Slot } },
		_entriesByModel: { [CooldownModel]: ModelEntry },
		_nextOrder: number,
		_destroyAuthoritativeOnExpiry: boolean,
		_reconcilePredictions: boolean,
		_destroyed: boolean,
	},
	{} :: typeof({ __index = CooldownRegistry })
))

function CooldownRegistry.new(
	binder: Binder.Binder<CooldownModel>,
	clock: Clock,
	destroyAuthoritativeOnExpiry: boolean,
	reconcilePredictions: boolean
): CooldownRegistry
	assert(t.table(binder) and Binder.isBinder(binder), "Bad binder")
	assert(t.callback(clock), "Bad clock")
	assert(t.boolean(destroyAuthoritativeOnExpiry), "Bad destroyAuthoritativeOnExpiry")
	assert(t.boolean(reconcilePredictions), "Bad reconcilePredictions")

	const self = setmetatable({}, CooldownRegistry) :: CooldownRegistry
	self._maid = Maid.new()
	self._binder = binder
	self._clock = clock
	self._slotsByOwner = {}
	self._entriesByModel = {}
	self._nextOrder = 0
	self._destroyAuthoritativeOnExpiry = destroyAuthoritativeOnExpiry
	self._reconcilePredictions = reconcilePredictions
	self._destroyed = false
	self._scheduler = self._maid:Add(CooldownExpiryScheduler.new(clock, function(cooldown)
		self:_refreshModel(cooldown)
	end))

	self._maid:Add(binder:GetClassAddedSignal():Connect(function(cooldown)
		self:Register(cooldown)
	end))
	self._maid:Add(binder:GetClassRemovingSignal():Connect(function(cooldown)
		self:Unregister(cooldown)
	end))
	for _, cooldown in binder:GetAll() do
		self:Register(cooldown)
	end

	return self
end

--[=[
	Registers a bound model immediately. Calls are idempotent so service creation
	can avoid waiting for binder signals.

	@within CooldownRegistry
	@param cooldown CooldownModel
]=]
function CooldownRegistry.Register(self: CooldownRegistry, cooldown: CooldownModel): ()
	assert(t.table(cooldown), "Bad cooldown")
	assert(not self._destroyed, "CooldownRegistry is destroyed")
	if self._entriesByModel[cooldown] then
		return
	end

	const entryMaid = Maid.new()
	const entry: ModelEntry = {
		Maid = entryMaid,
		Slot = nil,
		IsExpired = false,
	}
	self._entriesByModel[cooldown] = entry
	self._maid[cooldown] = entryMaid

	entryMaid:Add(cooldown.Changed:Connect(function()
		self:_refreshModel(cooldown)
	end))
	entryMaid:Add(function()
		self._scheduler:Cancel(cooldown)
		self:_removeFromSlot(cooldown, entry)
		self._entriesByModel[cooldown] = nil
	end)

	self:_refreshModel(cooldown)
end

--[=[
	Removes a previously registered model. Calls are idempotent.

	@within CooldownRegistry
	@param cooldown CooldownModel
]=]
function CooldownRegistry.Unregister(self: CooldownRegistry, cooldown: CooldownModel): ()
	assert(t.table(cooldown), "Bad cooldown")

	if self._entriesByModel[cooldown] then
		self._maid[cooldown] = nil
	end
end

--[=[
	Returns the effective active cooldown for an owner and key.

	@within CooldownRegistry
	@param owner Instance
	@param key string
	@return CooldownModel?
]=]
function CooldownRegistry.Get(self: CooldownRegistry, owner: Instance, key: string): CooldownModel?
	assert(t.Instance(owner), "Bad owner")
	assert(CooldownServiceUtils.isCooldownKey(key), "Bad key")

	const slots = self._slotsByOwner[owner]
	const slot = if slots then slots[key] else nil
	if slot and slot.Selected then
		if self:_isModelAlive(slot.Selected) then
			if not slot.Selected:IsActive() then
				self:_refreshModel(slot.Selected)
			end
		else
			self:Unregister(slot.Selected)
		end
	end

	return if slot then slot.Selected else nil
end

--[=[
	Observes the effective active cooldown for an owner and key. An authoritative
	client model replaces a local prediction without emitting an inactive gap.

	@within CooldownRegistry
	@param owner Instance
	@param key string
	@return Observable<CooldownModel?>
]=]
function CooldownRegistry.Observe(
	self: CooldownRegistry,
	owner: Instance,
	key: string
): Observable.Observable<CooldownModel?>
	assert(t.Instance(owner), "Bad owner")
	assert(CooldownServiceUtils.isCooldownKey(key), "Bad key")

	return Observable.new(function(sub)
		const slot = self:_getOrCreateSlot(owner, key)
		slot.ObserverCount += 1
		sub:Fire(self:Get(owner, key))
		const connection = slot.Changed:Connect(function(cooldown)
			sub:Fire(cooldown)
		end)

		return function()
			connection:Disconnect()
			slot.ObserverCount -= 1
			self:_tryCleanupSlot(slot)
		end
	end)
end

function CooldownRegistry._refreshModel(self: CooldownRegistry, cooldown: CooldownModel): ()
	const entry = self._entriesByModel[cooldown]
	if not entry then
		return
	end
	if not self:_isModelAlive(cooldown) then
		self:Unregister(cooldown)
		return
	end

	const state = cooldown:GetState()
	const isActive = state ~= nil and state.EndsAt > self:_readClock()
	if not state or not isActive then
		self._scheduler:Cancel(cooldown)
		self:_removeFromSlot(cooldown, entry)

		if state and not entry.IsExpired then
			entry.IsExpired = true
			if self._destroyAuthoritativeOnExpiry or state.IsPredicted then
				cooldown:GetFolder():Destroy()
			end
		end
		return
	end

	entry.IsExpired = false
	const slot = self:_getOrCreateSlot(state.Owner, state.Key)
	if entry.Slot ~= slot then
		self:_removeFromSlot(cooldown, entry)
		self._nextOrder += 1
		slot.Candidates[cooldown] = self._nextOrder
		entry.Slot = slot
	end

	self._scheduler:Schedule(cooldown, state.EndsAt)
	self:_recomputeSlot(slot)
end

function CooldownRegistry._removeFromSlot(self: CooldownRegistry, cooldown: CooldownModel, entry: ModelEntry): ()
	const slot = entry.Slot
	if not slot then
		return
	end

	entry.Slot = nil
	slot.Candidates[cooldown] = nil
	self:_recomputeSlot(slot)
	self:_tryCleanupSlot(slot)
end

function CooldownRegistry._getOrCreateSlot(self: CooldownRegistry, owner: Instance, key: string): Slot
	local slots = self._slotsByOwner[owner]
	if not slots then
		slots = {}
		self._slotsByOwner[owner] = slots
	end

	local slot = slots[key]
	if not slot then
		slot = {
			Owner = owner,
			Key = key,
			Candidates = {},
			Selected = nil,
			Changed = Signal.new(),
			ObserverCount = 0,
		}
		slots[key] = slot
	end

	return slot
end

function CooldownRegistry._recomputeSlot(self: CooldownRegistry, slot: Slot): ()
	local selected: CooldownModel? = nil
	local selectedState: CooldownState? = nil
	local selectedOrder = 0

	for cooldown, order in slot.Candidates do
		if not self:_isModelAlive(cooldown) then
			continue
		end

		const state = cooldown:GetState()
		if not state then
			continue
		end

		if
			not selectedState
			or (selectedState.IsPredicted and not state.IsPredicted)
			or (
				selectedState.IsPredicted == state.IsPredicted
				and (
					state.StartedAt > selectedState.StartedAt
					or (state.StartedAt == selectedState.StartedAt and order > selectedOrder)
				)
			)
		then
			selected = cooldown
			selectedState = state
			selectedOrder = order
		end
	end

	if slot.Selected ~= selected then
		slot.Selected = selected
		slot.Changed:Fire(selected)
	end

	if self._reconcilePredictions and selectedState and not selectedState.IsPredicted then
		for cooldown in slot.Candidates do
			if cooldown ~= selected and cooldown:IsPredicted() then
				cooldown:GetFolder():Destroy()
			end
		end
	end
end

function CooldownRegistry._isModelAlive(self: CooldownRegistry, cooldown: CooldownModel): boolean
	return self._entriesByModel[cooldown] ~= nil and getmetatable(cooldown) ~= nil
end

function CooldownRegistry._tryCleanupSlot(self: CooldownRegistry, slot: Slot): ()
	if next(slot.Candidates) ~= nil or slot.ObserverCount > 0 then
		return
	end

	const slots = self._slotsByOwner[slot.Owner]
	if not slots or slots[slot.Key] ~= slot then
		return
	end

	slots[slot.Key] = nil
	if next(slots) == nil then
		self._slotsByOwner[slot.Owner] = nil
	end
	slot.Changed:Destroy()
end

function CooldownRegistry._readClock(self: CooldownRegistry): number
	const currentTime = self._clock()
	assert(CooldownServiceUtils.isFiniteNumber(currentTime), "Clock returned bad time")
	return currentTime
end

function CooldownRegistry.Destroy(self: CooldownRegistry): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self._maid:DoCleaning()
	for _, slots in self._slotsByOwner do
		for _, slot in slots do
			slot.Changed:Destroy()
		end
	end
	table.clear(self._slotsByOwner)
	table.clear(self._entriesByModel)
end

return CooldownRegistry
