--!strict
--[=[
	@class TimeSyncConstants
]=]

const require = require("../../Loader").load()

local ByteNet = require("ByteNet")
local Table = require("TableUtils")

return Table.readonly({
	REMOTE_EVENT_NAME = "internal/timesync/event",
	REMOTE_FUNCTION_NAME = "internal/timesync/function",

	TIME_PRECISION = 1000,
	SYNC_INTERVAL = 5,
	INITIAL_SYNC_DELAY = 5,

	NET = ByteNet.defineNamespace("TimeSync", function()
		return {
			packets = {
				syncPulse = ByteNet.definePacket({
					value = ByteNet.float64,
				}),

				requestSync = ByteNet.definePacket({
					value = ByteNet.nothing,
				}),
			},

			queries = {
				delayRequest = ByteNet.defineQuery({
					request = ByteNet.float64,
					response = ByteNet.float64,
				}),
			},
		}
	end),
})
