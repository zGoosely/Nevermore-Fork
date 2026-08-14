--!strict
--[=[
	Validates cooldown data, creates tagged cooldown Folders, and provides the
	small heap operations used by the shared expiry scheduler.

	@util CooldownServiceUtils
]=]

const CollectionService = game:GetService("CollectionService")
const RunService = game:GetService("RunService")
const CooldownServiceConstants = require("./CooldownServiceConstants")
const CooldownServiceTypes = require("./CooldownServiceTypes")
const CooldownTypes = require("./CooldownTypes")
const t = require("@game/ReplicatedStorage/Packages/t")

type BurstCooldownValue = CooldownServiceTypes.BurstCooldownValue
type Clock = CooldownServiceTypes.Clock
type CooldownType = CooldownServiceTypes.CooldownType
type CooldownValue = CooldownServiceTypes.CooldownValue
type CooldownState = CooldownServiceTypes.CooldownState
type DefaultCooldownValue = CooldownServiceTypes.DefaultCooldownValue
type HeapEntry<T> = CooldownServiceTypes.HeapEntry<T>

const isDefaultCooldownValue = t.strictInterface({
	Duration = t.number,
})

const isBurstCooldownValue = t.strictInterface({
	Duration = t.number,
	Count = t.integer,
	Window = t.number,
	PenaltyDuration = t.number,
})

const CooldownServiceUtils = {}

--[=[
	Returns whether a value is a finite number.

	@within CooldownServiceUtils
	@param value any
	@return boolean
]=]
function CooldownServiceUtils.isFiniteNumber(value: any): boolean
	return t.number(value) and value > -math.huge and value < math.huge
end

--[=[
	Returns whether a value is a valid positive cooldown duration.

	@within CooldownServiceUtils
	@param value any
	@return boolean
]=]
function CooldownServiceUtils.isDuration(value: any): boolean
	return CooldownServiceUtils.isFiniteNumber(value) and value > 0
end

--[=[
	Returns whether a value is a nonempty cooldown lookup key.

	@within CooldownServiceUtils
	@param value any
	@return boolean
]=]
function CooldownServiceUtils.isCooldownKey(value: any): boolean
	return t.string(value) and value ~= ""
end

--[=[
	Returns whether a value is a valid default cooldown policy value.

	@within CooldownServiceUtils
	@param value any
	@return boolean
]=]
function CooldownServiceUtils.isDefaultCooldownValue(value: any): boolean
	return isDefaultCooldownValue(value) and CooldownServiceUtils.isDuration(value.Duration)
end

--[=[
	Returns whether a value is a valid burst cooldown policy value.

	@within CooldownServiceUtils
	@param value any
	@return boolean
]=]
function CooldownServiceUtils.isBurstCooldownValue(value: any): boolean
	return isBurstCooldownValue(value)
		and CooldownServiceUtils.isDuration(value.Duration)
		and value.Count >= 2
		and CooldownServiceUtils.isDuration(value.Window)
		and CooldownServiceUtils.isDuration(value.PenaltyDuration)
		and value.PenaltyDuration > value.Duration
end

--[=[
	Returns whether two burst values describe the same rolling policy.

	@within CooldownServiceUtils
	@param left BurstCooldownValue
	@param right BurstCooldownValue
	@return boolean
]=]
function CooldownServiceUtils.areBurstCooldownValuesEqual(left: BurstCooldownValue, right: BurstCooldownValue): boolean
	assert(CooldownServiceUtils.isBurstCooldownValue(left), "Bad left")
	assert(CooldownServiceUtils.isBurstCooldownValue(right), "Bad right")

	return left.Duration == right.Duration
		and left.Count == right.Count
		and left.Window == right.Window
		and left.PenaltyDuration == right.PenaltyDuration
end

--[=[
	Validates a cooldown type/value pair and returns its ordinary duration.

	@within CooldownServiceUtils
	@param cooldownType CooldownType
	@param cooldownValue CooldownValue
	@return number
]=]
function CooldownServiceUtils.getBaseDuration(cooldownType: CooldownType, cooldownValue: CooldownValue): number
	assert(t.string(cooldownType) and CooldownTypes:IsValue(cooldownType), "Bad cooldownType")

	if cooldownType == CooldownTypes.Default then
		assert(CooldownServiceUtils.isDefaultCooldownValue(cooldownValue), "Bad cooldownValue")
		return (cooldownValue :: DefaultCooldownValue).Duration
	end

	assert(cooldownType == CooldownTypes.Burst, "Bad cooldownType")
	assert(CooldownServiceUtils.isBurstCooldownValue(cooldownValue), "Bad cooldownValue")
	return (cooldownValue :: BurstCooldownValue).Duration
end

--[=[
	Validates an owner and case-sensitive cooldown lookup key.

	@within CooldownServiceUtils
	@param owner Instance
	@param key string
]=]
function CooldownServiceUtils.validateLookup(owner: Instance, key: string): ()
	assert(t.Instance(owner), "Bad owner")
	assert(CooldownServiceUtils.isCooldownKey(key), "Bad key")
end

--[=[
	Creates a completely initialized tagged cooldown Folder. Server-created
	Folders are authoritative; client-created Folders are local predictions.

	@within CooldownServiceUtils
	@param owner Instance
	@param key string
	@param duration number
	@param clock Clock?
	@return Folder
]=]
function CooldownServiceUtils.createCooldown(owner: Instance, key: string, duration: number, clock: Clock?): Folder
	CooldownServiceUtils.validateLookup(owner, key)
	assert(CooldownServiceUtils.isDuration(duration), "Bad duration")
	assert(t.optional(t.callback)(clock), "Bad clock")

	const resolvedClock = clock or tick
	const startedAt = resolvedClock()
	assert(CooldownServiceUtils.isFiniteNumber(startedAt), "Clock returned bad time")
	const endsAt = startedAt + duration
	assert(CooldownServiceUtils.isFiniteNumber(endsAt), "Bad duration")

	const folder = Instance.new("Folder")
	folder.Name = CooldownServiceConstants.FOLDER_NAME_PREFIX .. key
	folder.Archivable = false
	folder:SetAttribute(CooldownServiceConstants.KEY_ATTRIBUTE, key)
	folder:SetAttribute(CooldownServiceConstants.STARTED_AT_ATTRIBUTE, startedAt)
	folder:SetAttribute(CooldownServiceConstants.ENDS_AT_ATTRIBUTE, endsAt)
	folder:SetAttribute(CooldownServiceConstants.PREDICTED_ATTRIBUTE, RunService:IsClient())
	CollectionService:AddTag(folder, CooldownServiceConstants.TAG_NAME)
	folder.Parent = owner

	return folder
end

--[=[
	Reads and validates the complete cooldown state carried by a Folder. Returns
	nil while an externally tagged Folder is incomplete or malformed.

	@within CooldownServiceUtils
	@param folder Instance
	@return CooldownState?
]=]
function CooldownServiceUtils.readState(folder: Instance): CooldownState?
	if not t.instanceIsA("Folder")(folder) then
		return nil
	end

	const owner = folder.Parent
	const key = folder:GetAttribute(CooldownServiceConstants.KEY_ATTRIBUTE)
	const startedAt = folder:GetAttribute(CooldownServiceConstants.STARTED_AT_ATTRIBUTE)
	const endsAt = folder:GetAttribute(CooldownServiceConstants.ENDS_AT_ATTRIBUTE)
	const isPredicted = folder:GetAttribute(CooldownServiceConstants.PREDICTED_ATTRIBUTE)

	if
		not owner
		or not CooldownServiceUtils.isCooldownKey(key)
		or not CooldownServiceUtils.isFiniteNumber(startedAt)
		or not CooldownServiceUtils.isFiniteNumber(endsAt)
		or not t.boolean(isPredicted)
		or endsAt <= startedAt
	then
		return nil
	end

	return {
		Owner = owner,
		Key = key,
		StartedAt = startedAt,
		EndsAt = endsAt,
		IsPredicted = isPredicted,
	}
end

--[=[
	Inserts an entry into a minimum heap.

	@within CooldownServiceUtils
	@param heap { HeapEntry<T> }
	@param entry HeapEntry<T>
]=]
function CooldownServiceUtils.pushHeapEntry<T>(heap: { HeapEntry<T> }, entry: HeapEntry<T>): ()
	assert(t.table(heap), "Bad heap")
	assert(t.table(entry) and CooldownServiceUtils.isFiniteNumber(entry.Priority), "Bad entry")

	table.insert(heap, entry)
	local index = #heap

	while index > 1 do
		const parentIndex = math.floor(index / 2)
		if heap[parentIndex].Priority <= entry.Priority then
			break
		end

		heap[index] = heap[parentIndex]
		index = parentIndex
	end

	heap[index] = entry
end

--[=[
	Removes and returns the minimum entry from a heap.

	@within CooldownServiceUtils
	@param heap { HeapEntry<T> }
	@return HeapEntry<T>?
]=]
function CooldownServiceUtils.popHeapEntry<T>(heap: { HeapEntry<T> }): HeapEntry<T>?
	assert(t.table(heap), "Bad heap")

	const root = heap[1]
	const last = table.remove(heap)
	if not root or not last or #heap == 0 then
		return root
	end

	local index = 1
	while true do
		const leftIndex = index * 2
		if leftIndex > #heap then
			break
		end

		const rightIndex = leftIndex + 1
		local childIndex = leftIndex
		if rightIndex <= #heap and heap[rightIndex].Priority < heap[leftIndex].Priority then
			childIndex = rightIndex
		end
		if heap[childIndex].Priority >= last.Priority then
			break
		end

		heap[index] = heap[childIndex]
		index = childIndex
	end

	heap[index] = last
	return root
end

return CooldownServiceUtils
