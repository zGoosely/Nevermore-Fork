--!strict
--[=[
	Syncronizes time between the server and client. This creates a shared timestamp that can be used to reasonably time
	events between the server and client.

	@class TimeSyncService
]=]

const require = require("../Loader").load()

local RunService = game:GetService("RunService")

local BaseClock = require("BaseClock")
local Maid = require("Maid")
local MasterClock = require("MasterClock")
local Observable = require("Observable")
local Promise = require("Promise")
local Rx = require("Rx")
local SlaveClock = require("SlaveClock")
local TimeSyncUtils = require("TimeSyncUtils")

local TimeSyncService = {}
TimeSyncService.ServiceName = "TimeSyncService"

export type SyncedClock = BaseClock.BaseClock
export type TimeSyncService = typeof(setmetatable(
	{} :: {
		_clockPromise: Promise.Promise<SyncedClock>,
		_maid: Maid.Maid,
	},
	{} :: typeof({ __index = TimeSyncService })
))

function TimeSyncService.Init(self: TimeSyncService)
	assert(not (self :: any)._clockPromise, "TimeSyncService is already initialized!")

	self._maid = Maid.new()
	self._clockPromise = self._maid:Add(Promise.new())

	if not RunService:IsRunning() then
		self._clockPromise:Resolve(self:_buildMasterClock())
	elseif RunService:IsServer() then
		self._clockPromise:Resolve(self:_buildMasterClock())
	elseif RunService:IsClient() then
		-- This also handles play solo edgecase where
		self._clockPromise:Resolve(self:_promiseSlaveClock())
	else
		error("Bad RunService state")
	end
end

--[=[
	Returns true if the clock is synced. If the clock is synced, then it can
	be retrieved.

	@return boolean
]=]
function TimeSyncService.IsSynced(self: TimeSyncService): boolean
	if not RunService:IsRunning() then
		return true
	end

	assert(self._clockPromise, "TimeSyncService is not initialized")
	return self._clockPromise:IsFulfilled()
end

local function buildMockClock(): SyncedClock
	local mock = {}

	function mock.IsSynced(_this: SyncedClock): boolean
		return true
	end

	function mock.GetTime(_this: SyncedClock): number
		return tick()
	end

	function mock.GetPing(_this: SyncedClock): number
		return 0
	end

	function mock.GetClockFunction(_this: SyncedClock): BaseClock.ClockFunction
		return tick
	end

	function mock.ObservePing(_this: SyncedClock): Observable.Observable<number>
		return Rx.of(0) :: any
	end

	return mock
end

--[=[
	Waits for the synced clock, or throws an error.

	@yields
	@return MasterClock | SlaveClock
]=]
function TimeSyncService.WaitForSyncedClock(self: TimeSyncService): SyncedClock
	if not RunService:IsRunning() then
		return buildMockClock()
	end

	assert(self._clockPromise, "TimeSyncService is not initialized")
	return self._clockPromise:Wait()
end

--[=[
	Returns a synced clock if there is one available. Otherwise, returns nil.

	@return MasterClock | SlaveClock | nil
]=]
function TimeSyncService.GetSyncedClock(self: TimeSyncService): SyncedClock?
	if not RunService:IsRunning() then
		return buildMockClock()
	end

	assert(self._clockPromise, "TimeSyncService is not initialized")
	if self._clockPromise:IsFulfilled() then
		return self._clockPromise:Wait()
	end

	return nil
end

--[=[
	Promises a synced clock

	@return Promise<MasterClock | SlaveClock>
]=]
function TimeSyncService.PromiseSyncedClock(self: TimeSyncService): Promise.Promise<SyncedClock>
	if not RunService:IsRunning() then
		return Promise.resolved(buildMockClock())
	end

	assert(self._clockPromise, "TimeSyncService is not initialized")
	return Promise.resolved(self._clockPromise)
end

function TimeSyncService.ObserveSyncedClock(self: TimeSyncService): Observable.Observable<SyncedClock>
	return Rx.fromPromise(self:PromiseSyncedClock()) :: any
end

function TimeSyncService._buildMasterClock(self: TimeSyncService): MasterClock.MasterClock
	local clock = self._maid:Add(MasterClock.new())
	return clock
end

function TimeSyncService._promiseSlaveClock(self: TimeSyncService): Promise.Promise<SlaveClock.SlaveClock>
	local clock = self._maid:Add(SlaveClock.new())
	return TimeSyncUtils.promiseClockSynced(clock)
end

--[=[
	Cleans up the time syncronization service.
]=]
function TimeSyncService.Destroy(self: TimeSyncService)
	self._maid:DoCleaning()
end

return TimeSyncService
