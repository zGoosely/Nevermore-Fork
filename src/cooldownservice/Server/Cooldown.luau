--!strict
--[=[
	Authoritative server model for one tagged cooldown Folder.

	@class Cooldown
	@server
]=]

const require = require("../../Loader").load()

const CooldownBase = require("CooldownBase")
const CooldownServiceConstants = require("CooldownServiceConstants")
const CooldownServiceTypes = require("CooldownServiceTypes")
const CooldownServiceUtils = require("CooldownServiceUtils")

type Clock = CooldownServiceTypes.Clock

const Cooldown = setmetatable({}, CooldownBase)
Cooldown.ClassName = "Cooldown"
Cooldown.__index = Cooldown

export type Cooldown = typeof(setmetatable({} :: {}, {} :: typeof({ __index = Cooldown }))) & CooldownBase.CooldownBase

const modelsByFolder: { [Folder]: Cooldown } = setmetatable({}, { __mode = "kv" }) :: any

function Cooldown.new(folder: Folder, clock: Clock): Cooldown
	const existing = modelsByFolder[folder]
	if existing then
		return existing
	end

	const self = setmetatable(CooldownBase.new(folder, clock) :: any, Cooldown) :: Cooldown
	modelsByFolder[folder] = self
	self._maid:Add(function()
		if modelsByFolder[folder] == self then
			modelsByFolder[folder] = nil
		end
	end)
	return self
end

--[=[
	Restarts this cooldown from the current synchronized time.

	@within Cooldown
	@param duration number
]=]
function Cooldown.Restart(self: Cooldown, duration: number): ()
	assert(CooldownServiceUtils.isDuration(duration), "Bad duration")
	assert(self:GetState(), "Cannot restart an invalid cooldown")

	const startedAt = self:_readClock()
	const endsAt = startedAt + duration
	assert(CooldownServiceUtils.isFiniteNumber(endsAt), "Bad duration")
	self._obj:SetAttribute(CooldownServiceConstants.STARTED_AT_ATTRIBUTE, startedAt)
	self._obj:SetAttribute(CooldownServiceConstants.ENDS_AT_ATTRIBUTE, endsAt)
end

--[=[
	Extends an active cooldown by a positive duration.

	@within Cooldown
	@param duration number
	@return boolean
]=]
function Cooldown.AddTime(self: Cooldown, duration: number): boolean
	assert(CooldownServiceUtils.isDuration(duration), "Bad duration")

	const state = self:GetState()
	if not state or state.EndsAt <= self:_readClock() then
		return false
	end

	const endsAt = state.EndsAt + duration
	assert(CooldownServiceUtils.isFiniteNumber(endsAt), "Bad duration")
	self._obj:SetAttribute(CooldownServiceConstants.ENDS_AT_ATTRIBUTE, endsAt)
	return true
end

--[=[
	Removes time from an active cooldown. The cooldown is cleared when no time
	remains.

	@within Cooldown
	@param duration number
	@return boolean
]=]
function Cooldown.RemoveTime(self: Cooldown, duration: number): boolean
	assert(CooldownServiceUtils.isDuration(duration), "Bad duration")

	const state = self:GetState()
	if not state or state.EndsAt <= self:_readClock() then
		return false
	end

	const endsAt = state.EndsAt - duration
	if endsAt <= self:_readClock() or endsAt <= state.StartedAt then
		self:Clear()
	else
		self._obj:SetAttribute(CooldownServiceConstants.ENDS_AT_ATTRIBUTE, endsAt)
	end

	return true
end

--[=[
	Clears this cooldown by destroying its tagged Folder.

	@within Cooldown
]=]
function Cooldown.Clear(self: Cooldown): ()
	self._obj:Destroy()
end

return Cooldown
