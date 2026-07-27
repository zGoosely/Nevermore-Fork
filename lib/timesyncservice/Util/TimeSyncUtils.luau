--!strict
--[=[
	Helper functions for the TimeSyncService.
	@class TimeSyncUtils
]=]

const require = require("../../Loader").load()

local Promise = require("Promise")
local PromiseMaidUtils = require("PromiseMaidUtils")

local TimeSyncUtils = {}

--[=[
	Given a clock, returns a promise that resolves when the clock is syncronized.

	@param clock MasterClock | SlaveClock
	@return Promise<MasterClock | SlaveClock>
]=]
function TimeSyncUtils.promiseClockSynced(clock: any): Promise.Promise<any>
	if clock:IsSynced() then
		return Promise.resolved(clock)
	end

	assert(clock.SyncedEvent, "Somehow master clock isn't synced") -- Client clock only

	local promise = Promise.new()
	PromiseMaidUtils.whilePromise(promise, function(maid)
		maid:GiveTask(clock.SyncedEvent:Connect(function()
			if clock:IsSynced() then
				promise:Resolve(clock)
			end
		end))
	end)

	return promise
end

return TimeSyncUtils
