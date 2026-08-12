--!strict
--[=[
	Stable status names for [ActionExecution].

	@constants ActionExecutionStatuses
]=]

const require = require("../Loader").load()

const TableUtils = require("TableUtils")

return TableUtils.deepReadonly({
	RUNNING = "Running",
	CANCELLING = "Cancelling",
	SUCCEEDED = "Succeeded",
	FAILED = "Failed",
	CANCELLED = "Cancelled",
	TIMED_OUT = "TimedOut",
})
