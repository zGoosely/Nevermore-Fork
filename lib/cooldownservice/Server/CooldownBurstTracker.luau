--!strict
--[=[
	Tracks successful typed cooldown starts in rolling owner/key windows.

	@class CooldownBurstTracker
	@server
]=]

const require = require("../../Loader").load()

const CooldownServiceTypes = require("CooldownServiceTypes")
const CooldownServiceUtils = require("CooldownServiceUtils")
const Maid = require("Maid")
const t = require("t")

type BurstCooldownValue = CooldownServiceTypes.BurstCooldownValue
type Clock = CooldownServiceTypes.Clock

type BurstState = {
	Value: BurstCooldownValue,
	UseTimes: { number },
}

const CooldownBurstTracker = {}
CooldownBurstTracker.ClassName = "CooldownBurstTracker"
CooldownBurstTracker.__index = CooldownBurstTracker

export type CooldownBurstTracker = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_clock: Clock,
		_statesByOwner: { [Instance]: { [string]: BurstState } },
	},
	{} :: typeof({ __index = CooldownBurstTracker })
))

function CooldownBurstTracker.new(clock: Clock): CooldownBurstTracker
	assert(t.callback(clock), "Bad clock")

	const self = setmetatable({}, CooldownBurstTracker) :: CooldownBurstTracker
	self._maid = Maid.new()
	self._clock = clock
	self._statesByOwner = setmetatable({}, { __mode = "k" }) :: any

	return self
end

--[=[
	Records one successful use and returns its resolved cooldown duration.

	@within CooldownBurstTracker
	@param owner Instance
	@param key string
	@param value BurstCooldownValue
	@return number
]=]
function CooldownBurstTracker.RecordUse(
	self: CooldownBurstTracker,
	owner: Instance,
	key: string,
	value: BurstCooldownValue
): number
	CooldownServiceUtils.validateLookup(owner, key)
	assert(CooldownServiceUtils.isBurstCooldownValue(value), "Bad value")

	const now = self._clock()
	assert(CooldownServiceUtils.isFiniteNumber(now), "Clock returned bad time")

	local statesByKey = self._statesByOwner[owner]
	if not statesByKey then
		statesByKey = {}
		self._statesByOwner[owner] = statesByKey
	end

	local state = statesByKey[key]
	if not state or not CooldownServiceUtils.areBurstCooldownValuesEqual(state.Value, value) then
		state = {
			Value = table.freeze({
				Duration = value.Duration,
				Count = value.Count,
				Window = value.Window,
				PenaltyDuration = value.PenaltyDuration,
			}),
			UseTimes = {},
		}
		statesByKey[key] = state
	end

	while state.UseTimes[1] and now - state.UseTimes[1] > value.Window do
		table.remove(state.UseTimes, 1)
	end
	table.insert(state.UseTimes, now)

	if #state.UseTimes >= value.Count then
		table.clear(state.UseTimes)
		return value.PenaltyDuration
	end

	return value.Duration
end

--[=[
	Clears retained burst history for one owner/key pair.

	@within CooldownBurstTracker
	@param owner Instance
	@param key string
	@return boolean
]=]
function CooldownBurstTracker.Reset(self: CooldownBurstTracker, owner: Instance, key: string): boolean
	CooldownServiceUtils.validateLookup(owner, key)

	const statesByKey = self._statesByOwner[owner]
	if not statesByKey or not statesByKey[key] then
		return false
	end

	statesByKey[key] = nil
	if next(statesByKey) == nil then
		self._statesByOwner[owner] = nil
	end

	return true
end

function CooldownBurstTracker.Destroy(self: CooldownBurstTracker): ()
	self._maid:DoCleaning()
	table.clear(self._statesByOwner)
end

return CooldownBurstTracker
