--!strict
--[=[
	Constants for soft shutdown.

	@class SoftShutdownConstants
]=]
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly({
	IS_SOFT_SHUTDOWN_LOBBY_DATASTORE_KEY = "IsSoftShutdownLobby",
	IS_SOFT_SHUTDOWN_LOBBY_ATTRIBUTE = "IsSoftShutdownLobby",
	IS_SOFT_SHUTDOWN_UPDATING_ATTRIBUTE = "IsSoftshutdownRebootingServers",
	IS_SOFT_SHUTDOWN_RESERVE_SERVER_TELEPORT_KEY = "isSoftShutdownReserveServer",
	IS_SOFT_SHUTDOWN_UPDATED_SERVER_TELEPORT_KEY = "isSoftShutdownArrivingIntoUpdatedServer",
})
