--!strict
--[=[
	Maintains a reactive index from one attribute value to the Instances carrying
	that value. Instances may be added directly or tracked through a
	CollectionService tag.

	@class AttributeIndex
]=]

const require = require("../Loader").load()

const AttributeUtils = require("AttributeUtils")
const BaseObject = require("BaseObject")
const Brio = require("Brio")
const Maid = require("Maid")
const Observable = require("Observable")
const ObservableSet = require("ObservableSet")
const Rx = require("Rx")
const RxCollectionServiceUtils = require("RxCollectionServiceUtils")
const t = require("t")

export type AttributeIndexValue =
	boolean
	| number
	| string
	| BrickColor
	| CFrame
	| Color3
	| ColorSequence
	| EnumItem
	| Font
	| NumberRange
	| NumberSequence
	| Rect
	| UDim
	| UDim2
	| Vector2
	| Vector3

type Entry = {
	maid: Maid.Maid,
	references: number,
	value: AttributeIndexValue?,
}

const isAttributeIndexValue = t.intersection(t.any, function(value: any): boolean
	if typeof(value) == "number" and not t.number(value) then
		return false
	end

	return AttributeUtils.isValidAttributeType(typeof(value))
end)

const AttributeIndex = setmetatable({}, BaseObject)
AttributeIndex.ClassName = "AttributeIndex"
AttributeIndex.__index = AttributeIndex

export type AttributeIndex =
	typeof(setmetatable(
		{} :: {
			_attributeName: string,
			_destroyed: boolean,
			_entriesByInstance: { [Instance]: Entry },
			_setsByValue: { [AttributeIndexValue]: ObservableSet.ObservableSet<Instance> },
		},
		{} :: typeof({ __index = AttributeIndex })
	))
	& BaseObject.BaseObject<any>

function AttributeIndex.new(attributeName: string): AttributeIndex
	assert(t.string(attributeName) and AttributeUtils.isValidAttributeName(attributeName), "Bad attributeName")

	const self = setmetatable(BaseObject.new() :: any, AttributeIndex) :: AttributeIndex

	self._attributeName = attributeName
	self._destroyed = false
	self._entriesByInstance = {}
	self._setsByValue = {}
	self._maid:Add(function()
		self:_cleanup()
	end)

	return self
end

--[=[
	Adds an Instance to the index and follows future changes to the configured
	attribute. Multiple additions are reference-counted; each returned callback
	releases one reference.

	@within AttributeIndex
	@param instance Instance
	@return () -> ()
]=]
function AttributeIndex.Add(self: AttributeIndex, instance: Instance): () -> ()
	assert(t.instance(instance), "Bad instance")
	assert(not self._destroyed, "AttributeIndex is destroyed")

	local entry = self._entriesByInstance[instance]
	if entry == nil then
		const entryMaid = Maid.new()
		entry = {
			maid = entryMaid,
			references = 0,
			value = nil,
		}
		self._entriesByInstance[instance] = entry
		self._maid[instance] = entryMaid

		entryMaid:Add(instance:GetAttributeChangedSignal(self._attributeName):Connect(function()
			self:_updateInstance(instance, entry :: Entry)
		end))
		entryMaid:Add(instance.Destroying:Connect(function()
			self:_removeInstance(instance, entry :: Entry)
		end))

		self:_updateInstance(instance, entry)
	end

	entry.references += 1

	local isReleased = false
	return function()
		if isReleased then
			return
		end
		isReleased = true

		if self._destroyed then
			return
		end

		const currentEntry = self._entriesByInstance[instance]
		if currentEntry ~= entry then
			return
		end

		currentEntry.references -= 1
		assert(currentEntry.references >= 0, "AttributeIndex reference count underflow")
		if currentEntry.references == 0 then
			self:_removeInstance(instance, currentEntry)
		end
	end
end

--[=[
	Tracks every current and future Instance carrying a CollectionService tag.
	Removing the tag releases that tracking reference. The returned callback
	stops this tagged-instance source.

	@within AttributeIndex
	@param tagName string
	@return () -> ()
]=]
function AttributeIndex.TrackTagged(self: AttributeIndex, tagName: string): () -> ()
	assert(t.string(tagName) and tagName ~= "", "Bad tagName")
	assert(not self._destroyed, "AttributeIndex is destroyed")

	const trackingMaid = Maid.new()
	self._maid[trackingMaid] = trackingMaid

	trackingMaid:Add(RxCollectionServiceUtils.observeTaggedBrio(tagName):Subscribe(function(brio)
		if self._destroyed then
			return
		end

		const brioMaid, instance = brio:ToMaidAndValue()
		brioMaid:Add(self:Add(instance))
	end))

	local isStopped = false
	return function()
		if isStopped then
			return
		end
		isStopped = true

		if self._destroyed then
			trackingMaid:Destroy()
		else
			self._maid[trackingMaid] = nil
		end
	end
end

--[=[
	Forcibly removes an Instance from the index regardless of its current
	reference count.

	@within AttributeIndex
	@param instance Instance
	@return boolean
]=]
function AttributeIndex.Remove(self: AttributeIndex, instance: Instance): boolean
	assert(t.instance(instance), "Bad instance")
	assert(not self._destroyed, "AttributeIndex is destroyed")

	const entry = self._entriesByInstance[instance]
	if entry == nil then
		return false
	end

	self:_removeInstance(instance, entry)
	return true
end

--[=[
	Returns whether an Instance is currently tracked.

	@within AttributeIndex
	@param instance Instance
	@return boolean
]=]
function AttributeIndex.IsTracking(self: AttributeIndex, instance: Instance): boolean
	assert(t.instance(instance), "Bad instance")

	return self._entriesByInstance[instance] ~= nil
end

--[=[
	Returns an arbitrary tracked Instance carrying the given attribute value.

	@within AttributeIndex
	@param value AttributeIndexValue
	@return Instance?
]=]
function AttributeIndex.GetFirst(self: AttributeIndex, value: AttributeIndexValue): Instance?
	assert(isAttributeIndexValue(value), "Bad value")

	const observableSet = self._setsByValue[value]
	return if observableSet ~= nil then observableSet:GetFirstItem() else nil
end

--[=[
	Returns a snapshot of all tracked Instances carrying the given attribute
	value. Snapshot order is unspecified.

	@within AttributeIndex
	@param value AttributeIndexValue
	@return { Instance }
]=]
function AttributeIndex.GetAll(self: AttributeIndex, value: AttributeIndexValue): { Instance }
	assert(isAttributeIndexValue(value), "Bad value")

	const observableSet = self._setsByValue[value]
	return if observableSet ~= nil then observableSet:GetList() else {}
end

--[=[
	Observes snapshots of all tracked Instances carrying the given attribute
	value. Emits immediately and whenever membership changes.

	@within AttributeIndex
	@param value AttributeIndexValue
	@return Observable<{ Instance }>
]=]
function AttributeIndex.Observe(self: AttributeIndex, value: AttributeIndexValue): Observable.Observable<{ Instance }>
	assert(isAttributeIndexValue(value), "Bad value")
	assert(not self._destroyed, "AttributeIndex is destroyed")

	const observableSet = self:_getOrCreateSet(value)
	return observableSet:ObserveCount():Pipe({
		Rx.map(function(): { Instance }
			return observableSet:GetList()
		end),
	}) :: any
end

--[=[
	Observes each matching Instance as a Brio whose lifetime ends when the
	Instance leaves this attribute-value bucket.

	@within AttributeIndex
	@param value AttributeIndexValue
	@return Observable<Brio<Instance>>
]=]
function AttributeIndex.ObserveBrio(
	self: AttributeIndex,
	value: AttributeIndexValue
): Observable.Observable<Brio.Brio<Instance>>
	assert(isAttributeIndexValue(value), "Bad value")
	assert(not self._destroyed, "AttributeIndex is destroyed")

	return self:_getOrCreateSet(value):ObserveItemsBrio()
end

--[=[
	Observes the number of tracked Instances carrying the given attribute value.

	@within AttributeIndex
	@param value AttributeIndexValue
	@return Observable<number>
]=]
function AttributeIndex.ObserveCount(self: AttributeIndex, value: AttributeIndexValue): Observable.Observable<number>
	assert(isAttributeIndexValue(value), "Bad value")
	assert(not self._destroyed, "AttributeIndex is destroyed")

	return self:_getOrCreateSet(value):ObserveCount()
end

function AttributeIndex._getOrCreateSet(
	self: AttributeIndex,
	value: AttributeIndexValue
): ObservableSet.ObservableSet<Instance>
	const existing = self._setsByValue[value]
	if existing ~= nil then
		return existing
	end

	const observableSet = self._maid:Add(ObservableSet.new()) :: ObservableSet.ObservableSet<Instance>
	self._setsByValue[value] = observableSet
	return observableSet
end

function AttributeIndex._updateInstance(self: AttributeIndex, instance: Instance, entry: Entry): ()
	if self._entriesByInstance[instance] ~= entry then
		return
	end

	const newValue = AttributeUtils.getAttribute(instance, self._attributeName, nil)
	if newValue ~= nil then
		assert(isAttributeIndexValue(newValue), `Bad {self._attributeName} attribute value`)
	end
	if entry.value == newValue then
		return
	end

	const oldValue = entry.value
	entry.value = newValue

	if oldValue ~= nil then
		const oldSet = self._setsByValue[oldValue]
		assert(oldSet ~= nil, "AttributeIndex is missing an existing value set")
		oldSet:Remove(instance)
	end

	if newValue ~= nil then
		self:_getOrCreateSet(newValue):Add(instance)
	end
end

function AttributeIndex._removeInstance(self: AttributeIndex, instance: Instance, expectedEntry: Entry): ()
	const entry = self._entriesByInstance[instance]
	if entry ~= expectedEntry then
		return
	end

	self._entriesByInstance[instance] = nil

	if entry.value ~= nil then
		const observableSet = self._setsByValue[entry.value]
		assert(observableSet ~= nil, "AttributeIndex is missing an existing value set")
		observableSet:Remove(instance)
		entry.value = nil
	end

	self._maid[instance] = nil
end

function AttributeIndex._cleanup(self: AttributeIndex): ()
	if self._destroyed then
		return
	end
	self._destroyed = true

	table.clear(self._entriesByInstance)
	table.clear(self._setsByValue)
end

return AttributeIndex
