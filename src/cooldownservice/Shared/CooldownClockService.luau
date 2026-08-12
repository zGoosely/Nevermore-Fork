--!strict
--[=[
	Owns CooldownService's synchronized realm clock and hides TimeSyncService
	wiring from cooldown models and public helpers.

	@class CooldownClockService
]=]

const require = require("../../Loader").load()

const CooldownServiceUtils = require("CooldownServiceUtils")
const ServiceBag = require("ServiceBag")
const TimeSyncService = require("TimeSyncService")
const t = require("t")

const CooldownClockService = {}
CooldownClockService.ServiceName = "CooldownClockService"

export type CooldownClockService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_timeSyncService: TimeSyncService.TimeSyncService,
	},
	{} :: typeof({ __index = CooldownClockService })
))

function CooldownClockService.Init(self: CooldownClockService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._timeSyncService = self._serviceBag:GetService(TimeSyncService)
end

--[=[
	Returns the synchronized realm time, or the matching `tick` estimate before a
	client clock has synchronized.

	@within CooldownClockService
	@return number
]=]
function CooldownClockService.GetTime(self: CooldownClockService): number
	const syncedClock = self._timeSyncService:GetSyncedClock()
	const currentTime = if syncedClock then syncedClock:GetTime() else tick()
	assert(CooldownServiceUtils.isFiniteNumber(currentTime), "Clock returned bad time")
	return currentTime
end

return CooldownClockService
