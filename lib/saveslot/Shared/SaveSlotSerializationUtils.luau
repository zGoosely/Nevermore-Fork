--!strict
--[=[
	Schema-based serialization for SaveSlot network payloads.

	@util SaveSlotSerializationUtils
]=]

const require = require("../../Loader").load()

const SlotsProfileData = require("SlotsProfileData")
const SaveSlotTypes = require("SaveSlotTypes")
const SaveSlotUtils = require("SaveSlotUtils")
const Squash = require("Squash")

const MAX_U32 = 2 ^ 32 - 1
const GUID_BYTE_COUNT = 16

export type SlotState = {
	Sequence: number,
	ActiveSlotId: SaveSlotTypes.SlotId?,
	LastActiveSlotId: SaveSlotTypes.SlotId?,
	Metadata: { [string]: SaveSlotTypes.SaveSlotMetadata },
}

export type ActiveSlotDataSnapshot = {
	Sequence: number,
	SlotId: SaveSlotTypes.SlotId?,
	Data: any?,
}

const GUID_SCHEMA = Squash.buffer(GUID_BYTE_COUNT)
const SLOT_METADATA_SCHEMA = Squash.record({
	SlotId = GUID_SCHEMA,
	SlotIndex = Squash.u16(),
	SlotName = Squash.string(),
	CreatedTime = Squash.u32(),
	LastPlayedTime = Squash.u32(),
	Summary = Squash.string(),
})
const SLOT_STATE_SCHEMA = Squash.record({
	Sequence = Squash.u32(),
	ActiveSlotIndex = Squash.u16(),
	LastActiveSlotIndex = Squash.u16(),
	Metadata = Squash.array(SLOT_METADATA_SCHEMA),
})

const SaveSlotSerializationUtils = {}

local activeSlotDataSchema: any = nil

local function getActiveSlotDataSchema()
	if activeSlotDataSchema then
		return activeSlotDataSchema
	end

	const slotDataSchema = (SlotsProfileData :: any).SlotDataSchema
	assert(
		type(slotDataSchema) == "table"
			and type(slotDataSchema.ser) == "function"
			and type(slotDataSchema.des) == "function",
		"SlotsProfileData must export SlotDataSchema for SaveSlot active-data replication"
	)
	activeSlotDataSchema = Squash.record({
		Sequence = Squash.u32(),
		SlotId = Squash.opt(GUID_SCHEMA),
		Data = Squash.opt(slotDataSchema),
	})
	return activeSlotDataSchema
end

local function toU32(value: any): number
	return math.clamp(math.floor(if type(value) == "number" then value else 0), 0, MAX_U32)
end

local function guidToBuffer(slotId: string): buffer
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	const hexadecimal = string.gsub(string.lower(slotId), "%-", "")
	assert(#hexadecimal == GUID_BYTE_COUNT * 2 and string.match(hexadecimal, "^[0-9a-f]+$") ~= nil, "Bad GUID slotId")

	const result = buffer.create(GUID_BYTE_COUNT)
	for index = 0, GUID_BYTE_COUNT - 1 do
		const byte = tonumber(string.sub(hexadecimal, index * 2 + 1, index * 2 + 2), 16)
		buffer.writeu8(result, index, assert(byte, "Bad GUID byte"))
	end
	return result
end

local function bufferToGuid(value: buffer): string
	assert(buffer.len(value) == GUID_BYTE_COUNT, "Bad GUID buffer")
	const hexadecimal = table.create(GUID_BYTE_COUNT)
	for index = 0, GUID_BYTE_COUNT - 1 do
		table.insert(hexadecimal, string.format("%02x", buffer.readu8(value, index)))
	end

	const joined = table.concat(hexadecimal)
	return `{string.sub(joined, 1, 8)}-{string.sub(joined, 9, 12)}-{string.sub(joined, 13, 16)}-{string.sub(
		joined,
		17,
		20
	)}-{string.sub(joined, 21, 32)}`
end

--[=[
	Serializes all client-visible slot metadata and selection state. Record keys are
	schema-defined and never enter the payload.

	@within SaveSlotSerializationUtils
	@param sequence number
	@param metadataMap table
	@param activeSlotId string?
	@param lastActiveSlotId string?
	@return buffer
]=]
function SaveSlotSerializationUtils.serializeSlotState(
	sequence: number,
	metadataMap: any,
	activeSlotId: SaveSlotTypes.SlotId?,
	lastActiveSlotId: SaveSlotTypes.SlotId?
): buffer
	const metadata = SaveSlotUtils.getSlotList(metadataMap)
	const slotIndexes: { [string]: number } = {}
	const transportMetadata = table.create(#metadata)
	for _, value in metadata do
		slotIndexes[value.SlotId] = value.SlotIndex
		table.insert(transportMetadata, {
			SlotId = guidToBuffer(value.SlotId),
			SlotIndex = value.SlotIndex,
			SlotName = value.SlotName,
			CreatedTime = toU32(value.CreatedTime),
			LastPlayedTime = toU32(value.LastPlayedTime),
			Summary = value.Summary,
		})
	end

	const cursor = Squash.cursor()
	SLOT_STATE_SCHEMA.ser(cursor, {
		Sequence = toU32(sequence),
		ActiveSlotIndex = if activeSlotId then slotIndexes[activeSlotId] or 0 else 0,
		LastActiveSlotIndex = if lastActiveSlotId then slotIndexes[lastActiveSlotId] or 0 else 0,
		Metadata = transportMetadata,
	})
	return Squash.tobuffer(cursor)
end

--[=[
	Deserializes client-visible slot metadata and selection state.

	@within SaveSlotSerializationUtils
	@param data buffer
	@return SlotState
]=]
function SaveSlotSerializationUtils.deserializeSlotState(data: buffer): SlotState
	const decoded = SLOT_STATE_SCHEMA.des(Squash.frombuffer(data))
	const metadataMap: { [string]: SaveSlotTypes.SaveSlotMetadata } = {}
	const slotIdsByIndex: { [number]: string } = {}
	for _, value in decoded.Metadata do
		const slotId = bufferToGuid(value.SlotId)
		metadataMap[slotId] = {
			SlotId = slotId,
			SlotIndex = value.SlotIndex,
			SlotName = value.SlotName,
			CreatedTime = value.CreatedTime,
			LastPlayedTime = value.LastPlayedTime,
			Summary = value.Summary,
		}
		slotIdsByIndex[value.SlotIndex] = slotId
	end

	return {
		Sequence = decoded.Sequence,
		ActiveSlotId = slotIdsByIndex[decoded.ActiveSlotIndex],
		LastActiveSlotId = slotIdsByIndex[decoded.LastActiveSlotIndex],
		Metadata = metadataMap,
	}
end

--[=[
	Serializes one snapshot of the active slot using the consuming game's exported
	`SlotsProfileData.SlotDataSchema`.

	@within SaveSlotSerializationUtils
	@param sequence number
	@param slotId string?
	@param slotData any?
	@return buffer
]=]
function SaveSlotSerializationUtils.serializeActiveSlotData(
	sequence: number,
	slotId: SaveSlotTypes.SlotId?,
	slotData: any?
): buffer
	const cursor = Squash.cursor()
	getActiveSlotDataSchema().ser(cursor, {
		Sequence = toU32(sequence),
		SlotId = if slotId then guidToBuffer(slotId) else nil,
		Data = slotData,
	})
	return Squash.tobuffer(cursor)
end

--[=[
	Deserializes one active-slot snapshot.

	@within SaveSlotSerializationUtils
	@param data buffer
	@return ActiveSlotDataSnapshot
]=]
function SaveSlotSerializationUtils.deserializeActiveSlotData(data: buffer): ActiveSlotDataSnapshot
	const decoded = getActiveSlotDataSchema().des(Squash.frombuffer(data))
	return {
		Sequence = decoded.Sequence,
		SlotId = if decoded.SlotId then bufferToGuid(decoded.SlotId) else nil,
		Data = decoded.Data,
	}
end

return SaveSlotSerializationUtils
