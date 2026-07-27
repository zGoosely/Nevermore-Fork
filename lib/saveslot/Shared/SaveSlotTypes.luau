--!strict
--[=[
	Shared SaveSlot types.

	@class SaveSlotTypes
]=]

export type SlotId = string

export type SaveSlotMetadata = {
	SlotId: SlotId,
	SlotIndex: number,
	SlotName: string,
	CreatedTime: number,
	LastPlayedTime: number,
	Summary: string,
}

export type SaveSlotMetadataInput = {
	SlotName: string?,
	Summary: string?,
}

export type SaveSlotState = {
	ActiveSlotId: SlotId | string,
	LastActiveSlotId: SlotId | string,
	Metadata: { [SlotId]: SaveSlotMetadata },
	Slots: { [SlotId]: any },
}

export type MutationResult = {
	success: boolean,
	error: string,
	slotId: string,
}

export type SaveSlotConfig = {
	explicitSelection: boolean,
	maxSlotCount: number,
}

return table.freeze({})
