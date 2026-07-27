--!strict
--[=[
	Master clock on the server
	@class MasterClock
]=]

const require = require("../../Loader").load()

local BaseClock = require("BaseClock")
local BaseObject = require("BaseObject")
local Observable = require("Observable")
local Rx = require("Rx")
local TableUtils = require("TableUtils")
local TimeSyncConstants = require("TimeSyncConstants")

local MasterClock = setmetatable({}, BaseObject)
MasterClock.__index = MasterClock
MasterClock.ClassName = "MasterClock"

export type MasterClock =
	typeof(setmetatable(
		{} :: {
			_clockFunction: BaseClock.ClockFunction,
		},
		{} :: typeof({ __index = MasterClock })
	))
	& BaseObject.BaseObject<any>
	& BaseClock.BaseClock

--[=[
	Constructs a new MasterClock

	@param remoteEvent RemoteEvent
	@param remoteFunction RemoteFunction
	@return MasterClock
]=]
function MasterClock.new(): MasterClock
	local self: MasterClock = setmetatable(BaseObject.new() :: any, MasterClock)

	const requestSync = TimeSyncConstants.NET.packets.requestSync
	local function handleRequestSync(_, player: Player)
		TimeSyncConstants.NET.packets.syncPulse.sendTo(self:GetTime(), player)
	end
	requestSync.listen(handleRequestSync)
	self._maid:GiveTask(function()
		const listeners = requestSync.getListeners()
		const index = table.find(listeners, handleRequestSync)
		if index then
			TableUtils.swapRemove(listeners, index)
		end
	end)

	const delayRequest = TimeSyncConstants.NET.queries.delayRequest
	local function handleDelayRequest(timeThree: number)
		return self:GetTime() - timeThree
	end
	delayRequest.listen(handleDelayRequest)
	self._maid:GiveTask(function()
		const listeners = delayRequest.getListeners()
		const index = table.find(listeners, handleDelayRequest)
		if index then
			TableUtils.swapRemove(listeners, index)
		end
	end)

	self._clockFunction = function()
		return self:GetTime()
	end

	self:_startPeriodicSync()

	return self
end

--[=[
	Gets a function that can be used as a clock, like `time` and `tick` are.

	@return function
]=]
function MasterClock.GetClockFunction(self: MasterClock): BaseClock.ClockFunction
	return self._clockFunction
end

--[=[
	Observes how much ping the clock has

	@return Observable<number>
]=]
function MasterClock.ObservePing(_self: MasterClock): Observable.Observable<number>
	return Rx.of(0) :: any
end

--[=[
	Returns true if the manager has synced with the server
	@return boolean
]=]
function MasterClock.IsSynced(_self: MasterClock): boolean
	return true
end

--[=[
	Returns estimated ping in seconds
	@return number
]=]
function MasterClock.GetPing(_self: MasterClock): number
	return 0
end

--[=[
	Returns the sycncronized time
	@return number
]=]
function MasterClock.GetTime(_self: MasterClock): number
	return tick()
end

function MasterClock._forceSync(self: MasterClock): ()
	TimeSyncConstants.NET.packets.syncPulse.sendToAll(self:GetTime())
end

function MasterClock._startPeriodicSync(self: MasterClock)
	local isRunning = true
	self._maid:GiveTask(function()
		isRunning = false
	end)

	local function scheduleNextSync()
		if not isRunning then
			return
		end

		task.delay(TimeSyncConstants.SYNC_INTERVAL, function()
			if not isRunning then
				return
			end

			self:_forceSync()
			scheduleNextSync()
		end)
	end

	self._maid:GiveTask(task.delay(TimeSyncConstants.INITIAL_SYNC_DELAY, function()
		if isRunning then
			self:_forceSync()
			scheduleNextSync()
		end
	end))
end

return MasterClock
