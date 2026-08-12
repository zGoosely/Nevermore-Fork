--!strict
--[=[
	ByteNet transport for player-owned save-slot mutations and the local player's
	active-slot mirror. Inactive slot contents remain server-only.

	@network SaveSlotNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("SaveSlots", function()
	const mutationResult = ByteNet.struct({
		success = ByteNet.bool,
		error = ByteNet.string,
		slotId = ByteNet.string,
	})
	return {
		packets = {
			slotStateChanged = ByteNet.definePacket({
				value = ByteNet.buff,
			}),
			activeSlotInvalidated = ByteNet.definePacket({
				value = ByteNet.uint32,
			}),
			activeSlotSubscriptionChanged = ByteNet.definePacket({
				value = ByteNet.bool,
			}),
		},
		queries = {
			getConfig = ByteNet.defineQuery({
				request = ByteNet.nothing,
				response = ByteNet.struct({
					explicitSelection = ByteNet.bool,
					maxSlotCount = ByteNet.uint16,
				}),
			}),
			getSlotState = ByteNet.defineQuery({
				request = ByteNet.nothing,
				response = ByteNet.buff,
			}),
			getActiveSlotData = ByteNet.defineQuery({
				request = ByteNet.bool,
				response = ByteNet.buff,
			}),
			selectSlot = ByteNet.defineQuery({
				request = ByteNet.string,
				response = mutationResult,
			}),
			createSlot = ByteNet.defineQuery({
				request = ByteNet.struct({
					slotIndex = ByteNet.uint16,
					slotName = ByteNet.string,
					summary = ByteNet.string,
				}),
				response = mutationResult,
			}),
			deleteSlot = ByteNet.defineQuery({
				request = ByteNet.string,
				response = mutationResult,
			}),
			setMetadata = ByteNet.defineQuery({
				request = ByteNet.struct({
					slotId = ByteNet.string,
					hasSlotName = ByteNet.bool,
					slotName = ByteNet.string,
					hasSummary = ByteNet.bool,
					summary = ByteNet.string,
				}),
				response = mutationResult,
			}),
		},
	}
end))
