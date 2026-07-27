--!strict
--[=[
	Pure helpers for SaveSlot data and paths.

	@util SaveSlotUtils
]=]

const require = require("../../Loader").load()

const SaveSlotConstants = require("SaveSlotConstants")
const SaveSlotTypes = require("SaveSlotTypes")

const SaveSlotUtils = {}

--[=[
	Returns whether a value is a non-empty slot ID that is safe to place inside a
	dot-separated PlayerDataStoreService path.

	@within SaveSlotUtils
	@param value any
	@return boolean
]=]
function SaveSlotUtils.isSlotId(value: any): boolean
	return type(value) == "string" and value ~= "" and string.find(value, ".", 1, true) == nil
end

--[=[
	Converts a value into a slot ID, returning nil when it is not valid.

	@within SaveSlotUtils
	@param value any
	@return string?
]=]
function SaveSlotUtils.toOptionalSlotId(value: any): SaveSlotTypes.SlotId?
	return if SaveSlotUtils.isSlotId(value) then value else nil
end

--[=[
	Returns whether a value is a valid non-empty dot-separated path relative to a
	slot's data table.

	@within SaveSlotUtils
	@param path any
	@return boolean
]=]
function SaveSlotUtils.isDataPath(path: any): boolean
	if type(path) ~= "string" or path == "" then
		return false
	end

	if string.sub(path, 1, 1) == "." or string.sub(path, -1) == "." then
		return false
	end

	return string.find(path, "..", 1, true) == nil
end

--[=[
	Builds the PlayerDataStoreService path for a slot or one value inside that slot.

	@within SaveSlotUtils
	@param slotId string
	@param path string?
	@return string
]=]
function SaveSlotUtils.getSlotPath(slotId: SaveSlotTypes.SlotId, path: string?): string
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	if path == nil or path == "" then
		return `{SaveSlotConstants.SLOTS_PATH}.{slotId}`
	end

	assert(SaveSlotUtils.isDataPath(path), "Bad path")
	return `{SaveSlotConstants.SLOTS_PATH}.{slotId}.{path}`
end

--[=[
	Sanitizes a metadata map into a slot list sorted by slot index and then slot ID.

	@within SaveSlotUtils
	@param metadataMap any
	@return { SaveSlotMetadata }
]=]
function SaveSlotUtils.getSlotList(metadataMap: any): { SaveSlotTypes.SaveSlotMetadata }
	const result: { SaveSlotTypes.SaveSlotMetadata } = {}
	if type(metadataMap) ~= "table" then
		return result
	end

	for slotId, value in metadataMap do
		if not SaveSlotUtils.isSlotId(slotId) or type(value) ~= "table" then
			continue
		end

		const slotIndex = value.SlotIndex
		if type(slotIndex) ~= "number" or slotIndex % 1 ~= 0 or slotIndex < 1 then
			continue
		end

		table.insert(result, {
			SlotId = slotId,
			SlotIndex = slotIndex,
			SlotName = if type(value.SlotName) == "string" then value.SlotName else `Slot {slotIndex}`,
			CreatedTime = if type(value.CreatedTime) == "number" then value.CreatedTime else 0,
			LastPlayedTime = if type(value.LastPlayedTime) == "number" then value.LastPlayedTime else 0,
			Summary = if type(value.Summary) == "string" then value.Summary else "",
		})
	end

	table.sort(result, function(left, right)
		if left.SlotIndex == right.SlotIndex then
			return left.SlotId < right.SlotId
		end
		return left.SlotIndex < right.SlotIndex
	end)

	return result
end

--[=[
	Returns sanitized metadata for a slot ID.

	@within SaveSlotUtils
	@param metadataMap any
	@param slotId string
	@return SaveSlotMetadata?
]=]
function SaveSlotUtils.getSlotMetadata(metadataMap: any, slotId: SaveSlotTypes.SlotId): SaveSlotTypes.SaveSlotMetadata?
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")

	for _, metadata in SaveSlotUtils.getSlotList(metadataMap) do
		if metadata.SlotId == slotId then
			return metadata
		end
	end

	return nil
end

--[=[
	Returns the ID assigned to a slot index.

	@within SaveSlotUtils
	@param metadataMap any
	@param slotIndex number
	@return string?
]=]
function SaveSlotUtils.getSlotIdFromIndex(metadataMap: any, slotIndex: number): SaveSlotTypes.SlotId?
	for _, metadata in SaveSlotUtils.getSlotList(metadataMap) do
		if metadata.SlotIndex == slotIndex then
			return metadata.SlotId
		end
	end

	return nil
end

return SaveSlotUtils
