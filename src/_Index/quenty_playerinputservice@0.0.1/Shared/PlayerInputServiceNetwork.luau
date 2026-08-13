--!strict
--[=[
	Compact semantic input protocol for PlayerInputService. Clients can only send
	an action ID and Begin/End state.

	@network PlayerInputServiceNetwork
]=]
const ByteNet = require("@game/ReplicatedStorage/Packages/ByteNet")
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("PlayerInputs", function()
	const serializedInputType = ByteNet.struct({
		Kind = ByteNet.uint8,
		Name = ByteNet.string,
		Modifiers = ByteNet.optional(ByteNet.array(ByteNet.string)),
	})

	const bindingOverride = ByteNet.struct({
		ActionId = ByteNet.uint16,
		InputModeName = ByteNet.string,
		InputTypes = ByteNet.array(serializedInputType),
		Clear = ByteNet.bool,
	})

	const initialState = ByteNet.struct({
		AllowedActionIds = ByteNet.array(ByteNet.uint16),
		BindingOverrides = ByteNet.array(bindingOverride),
		ContextName = ByteNet.string,
		PolicyRevision = ByteNet.uint32,
		BindingRevision = ByteNet.uint32,
	})

	return {
		packets = {
			inputChanged = ByteNet.definePacket({
				value = ByteNet.struct({
					actionId = ByteNet.uint16,
					state = ByteNet.uint8,
				}),
			}),
			policyChanged = ByteNet.definePacket({
				value = ByteNet.struct({
					revision = ByteNet.uint32,
					addedActionIds = ByteNet.array(ByteNet.uint16),
					removedActionIds = ByteNet.array(ByteNet.uint16),
					contextName = ByteNet.string,
				}),
			}),
			bindingOverrideChanged = ByteNet.definePacket({
				value = ByteNet.struct({
					revision = ByteNet.uint32,
					bindingOverride = bindingOverride,
				}),
			}),
			forceRelease = ByteNet.definePacket({
				value = ByteNet.struct({
					actionId = ByteNet.uint16,
				}),
			}),
			forceReleaseAll = ByteNet.definePacket({
				value = ByteNet.nothing,
			}),
		},
		queries = {
			requestInitialState = ByteNet.defineQuery({
				request = ByteNet.nothing,
				response = ByteNet.optional(initialState),
			}),
		},
	}
end))
