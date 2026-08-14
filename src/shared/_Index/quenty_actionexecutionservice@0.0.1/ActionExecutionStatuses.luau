--!strict
--[=[
	Stable status names for [ActionExecution].

	@constants ActionExecutionStatuses
]=]
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly({
	RUNNING = "Running",
	CANCELLING = "Cancelling",
	SUCCEEDED = "Succeeded",
	FAILED = "Failed",
	CANCELLED = "Cancelled",
	TIMED_OUT = "TimedOut",
})
