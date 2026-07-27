--!strict
--[=[
	Schedules all cooldown expirations through one minimum heap and one heartbeat.

	@class CooldownExpiryScheduler
]=]

const RunService = game:GetService("RunService")

const require = require("../../Loader").load()

const CooldownServiceTypes = require("CooldownServiceTypes")
const CooldownServiceUtils = require("CooldownServiceUtils")
const Maid = require("Maid")
const t = require("t")

type Clock = CooldownServiceTypes.Clock
type CooldownModel = CooldownServiceTypes.CooldownModel
type HeapEntry<T> = CooldownServiceTypes.HeapEntry<T>

export type ExpiredCallback = (cooldown: CooldownModel) -> ()

const CooldownExpiryScheduler = {}
CooldownExpiryScheduler.ClassName = "CooldownExpiryScheduler"
CooldownExpiryScheduler.__index = CooldownExpiryScheduler

export type CooldownExpiryScheduler = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_clock: Clock,
		_expiredCallback: ExpiredCallback,
		_heap: { HeapEntry<CooldownModel> },
		_versions: { [CooldownModel]: number },
		_nextVersion: number,
		_destroyed: boolean,
	},
	{} :: typeof({ __index = CooldownExpiryScheduler })
))

function CooldownExpiryScheduler.new(clock: Clock, expiredCallback: ExpiredCallback): CooldownExpiryScheduler
	assert(t.callback(clock), "Bad clock")
	assert(t.callback(expiredCallback), "Bad expiredCallback")

	const self = setmetatable({}, CooldownExpiryScheduler) :: CooldownExpiryScheduler
	self._maid = Maid.new()
	self._clock = clock
	self._expiredCallback = expiredCallback
	self._heap = {}
	self._versions = {}
	self._nextVersion = 0
	self._destroyed = false

	if RunService:IsRunning() then
		self._maid:Add(RunService.Heartbeat:Connect(function()
			self:Step()
		end))
	end

	return self
end

--[=[
	Schedules or reschedules one cooldown at an absolute synchronized timestamp.

	@within CooldownExpiryScheduler
	@param cooldown CooldownModel
	@param endsAt number
]=]
function CooldownExpiryScheduler.Schedule(self: CooldownExpiryScheduler, cooldown: CooldownModel, endsAt: number): ()
	assert(t.table(cooldown), "Bad cooldown")
	assert(CooldownServiceUtils.isFiniteNumber(endsAt), "Bad endsAt")
	assert(not self._destroyed, "CooldownExpiryScheduler is destroyed")

	self._nextVersion += 1
	const version = self._nextVersion
	self._versions[cooldown] = version
	CooldownServiceUtils.pushHeapEntry(self._heap, {
		Priority = endsAt,
		Value = cooldown,
		Version = version,
	})
end

--[=[
	Cancels any active expiry entry for a cooldown.

	@within CooldownExpiryScheduler
	@param cooldown CooldownModel
]=]
function CooldownExpiryScheduler.Cancel(self: CooldownExpiryScheduler, cooldown: CooldownModel): ()
	assert(t.table(cooldown), "Bad cooldown")

	self._versions[cooldown] = nil
	if next(self._versions) == nil then
		table.clear(self._heap)
	end
end

--[=[
	Processes every cooldown due at the current clock time. Runtime heartbeats call
	this automatically; tests can call it after advancing a fake clock.

	@within CooldownExpiryScheduler
]=]
function CooldownExpiryScheduler.Step(self: CooldownExpiryScheduler): ()
	if self._destroyed then
		return
	end

	const currentTime = self._clock()
	assert(CooldownServiceUtils.isFiniteNumber(currentTime), "Clock returned bad time")

	while true do
		const entry = self._heap[1]
		if not entry or entry.Priority > currentTime then
			break
		end

		CooldownServiceUtils.popHeapEntry(self._heap)
		if self._versions[entry.Value] == entry.Version then
			self._versions[entry.Value] = nil
			self._expiredCallback(entry.Value)
		end
	end

	if next(self._versions) == nil then
		table.clear(self._heap)
	end
end

function CooldownExpiryScheduler.Destroy(self: CooldownExpiryScheduler): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	table.clear(self._heap)
	table.clear(self._versions)
	self._maid:DoCleaning()
end

return CooldownExpiryScheduler
