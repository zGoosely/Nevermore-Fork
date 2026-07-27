--!strict
--[=[
	ByteNet protocol schema for DeathReport with compact uint8 Player IDs.

	@network DeathReportNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("DeathReport", function()
	return {
		packets = {
			deathReport = ByteNet.definePacket({
				value = ByteNet.struct({
					playerId = ByteNet.optional(ByteNet.uint8),
					killerPlayerId = ByteNet.optional(ByteNet.uint8),
					adornee = ByteNet.optional(ByteNet.inst),
					killerAdornee = ByteNet.optional(ByteNet.inst),
					weaponInstance = ByteNet.optional(ByteNet.inst),
				}),
			}),
		},
	}
end))
