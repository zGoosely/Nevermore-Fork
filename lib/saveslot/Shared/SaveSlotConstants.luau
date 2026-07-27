--!strict
--[=[
	Constants shared by SaveSlotService and SaveSlotServiceClient.

	@class SaveSlotConstants
]=]

const SaveSlotConstants = {}

SaveSlotConstants.ROOT_PATH = "SaveSlots"
SaveSlotConstants.ACTIVE_SLOT_ID_PATH = "SaveSlots.ActiveSlotId"
SaveSlotConstants.LAST_ACTIVE_SLOT_ID_PATH = "SaveSlots.LastActiveSlotId"
SaveSlotConstants.METADATA_PATH = "SaveSlots.Metadata"
SaveSlotConstants.SLOTS_PATH = "SaveSlots.Slots"
SaveSlotConstants.TELEPORT_DATA_SLOT_KEY = "IncomingSaveSlotId"
SaveSlotConstants.DEFAULT_SLOT_INDEX = 1
SaveSlotConstants.MAX_SLOT_COUNT = 65_535

return table.freeze(SaveSlotConstants)
