--!strict
--[=[
	Creates, queries, observes, and expires authoritative cooldowns attached to
	arbitrary Instance owners.

	@class CooldownService
	@server
]=]

const require = require("../Loader").load()

const Cooldown = require("Cooldown")
const CooldownBindersServer = require("CooldownBindersServer")
const CooldownBurstTracker = require("CooldownBurstTracker")
const CooldownClockService = require("CooldownClockService")
const CooldownRegistry = require("CooldownRegistry")
const CooldownServiceTypes = require("CooldownServiceTypes")
const CooldownServiceUtils = require("CooldownServiceUtils")
const CooldownTypes = require("CooldownTypes")
const Maid = require("Maid")
const Observable = require("Observable")
const Rx = require("Rx")
const ServiceBag = require("ServiceBag")
const t = require("t")

type Clock = CooldownServiceTypes.Clock
type CooldownType = CooldownServiceTypes.CooldownType
type CooldownValue = CooldownServiceTypes.CooldownValue

const CooldownService = {}
CooldownService.ServiceName = "CooldownService"
CooldownService.ServerOnly = true

export type CooldownService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_cooldownClockService: CooldownClockService.CooldownClockService,
		_binders: CooldownBindersServer.CooldownBindersServer,
		_clock: Clock,
		_registry: CooldownRegistry.CooldownRegistry,
		_burstTracker: CooldownBurstTracker.CooldownBurstTracker,
	},
	{} :: typeof({ __index = CooldownService })
))

function CooldownService.Init(self: CooldownService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._cooldownClockService = self._serviceBag:GetService(CooldownClockService)
	self._binders = self._serviceBag:GetService(CooldownBindersServer) :: any
	self._clock = function()
		return self._cooldownClockService:GetTime()
	end
	self._registry = self._maid:Add(CooldownRegistry.new(self._binders.Cooldown :: any, self._clock, true, false))
	self._burstTracker = self._maid:Add(CooldownBurstTracker.new(self._clock))
end

--[=[
	Starts a cooldown when the owner/key pair is ready. Returns nil without
	changing the active cooldown when the pair is already cooling down.

	@within CooldownService
	@param owner Instance
	@param key string
	@param duration number
	@return Cooldown?
]=]
function CooldownService.StartCooldown(
	self: CooldownService,
	owner: Instance,
	key: string,
	duration: number
): Cooldown.Cooldown?
	CooldownServiceUtils.validateLookup(owner, key)
	assert(CooldownServiceUtils.isDuration(duration), "Bad duration")

	if self._registry:Get(owner, key) then
		return nil
	end

	self._burstTracker:Reset(owner, key)
	return self:_createCooldown(owner, key, duration)
end

--[=[
	Starts a typed default or rolling burst cooldown when the owner/key pair is
	ready. A rejected start does not advance burst history.

	@within CooldownService
	@param owner Instance
	@param key string
	@param cooldownType CooldownType
	@param cooldownValue CooldownValue
	@return Cooldown?
]=]
function CooldownService.StartTypedCooldown(
	self: CooldownService,
	owner: Instance,
	key: string,
	cooldownType: CooldownType,
	cooldownValue: CooldownValue
): Cooldown.Cooldown?
	CooldownServiceUtils.validateLookup(owner, key)
	const baseDuration = CooldownServiceUtils.getBaseDuration(cooldownType, cooldownValue)

	if self._registry:Get(owner, key) then
		return nil
	end

	local duration = baseDuration
	if cooldownType == CooldownTypes.Burst then
		duration = self._burstTracker:RecordUse(owner, key, cooldownValue :: CooldownServiceTypes.BurstCooldownValue)
	else
		self._burstTracker:Reset(owner, key)
	end

	return self:_createCooldown(owner, key, duration)
end

--[=[
	Restarts the active cooldown or creates it when the owner/key pair is ready.

	@within CooldownService
	@param owner Instance
	@param key string
	@param duration number
	@return Cooldown
]=]
function CooldownService.RestartCooldown(
	self: CooldownService,
	owner: Instance,
	key: string,
	duration: number
): Cooldown.Cooldown
	CooldownServiceUtils.validateLookup(owner, key)
	assert(CooldownServiceUtils.isDuration(duration), "Bad duration")

	self._burstTracker:Reset(owner, key)
	const cooldown = self:GetCooldown(owner, key)
	if cooldown then
		cooldown:Restart(duration)
		return cooldown
	end

	return self:_createCooldown(owner, key, duration)
end

--[=[
	Returns the active cooldown for an owner/key pair.

	@within CooldownService
	@param owner Instance
	@param key string
	@return Cooldown?
]=]
function CooldownService.GetCooldown(self: CooldownService, owner: Instance, key: string): Cooldown.Cooldown?
	CooldownServiceUtils.validateLookup(owner, key)
	return self._registry:Get(owner, key) :: any
end

--[=[
	Returns whether an owner/key pair currently has an active cooldown.

	@within CooldownService
	@param owner Instance
	@param key string
	@return boolean
]=]
function CooldownService.IsOnCooldown(self: CooldownService, owner: Instance, key: string): boolean
	return self:GetCooldown(owner, key) ~= nil
end

--[=[
	Returns the current nonnegative remaining duration for an owner/key pair.

	@within CooldownService
	@param owner Instance
	@param key string
	@return number
]=]
function CooldownService.GetRemainingTime(self: CooldownService, owner: Instance, key: string): number
	const cooldown = self:GetCooldown(owner, key)
	return if cooldown then cooldown:GetRemainingTime() else 0
end

--[=[
	Observes the active cooldown for an owner/key pair.

	@within CooldownService
	@param owner Instance
	@param key string
	@return Observable<Cooldown?>
]=]
function CooldownService.ObserveCooldown(
	self: CooldownService,
	owner: Instance,
	key: string
): Observable.Observable<Cooldown.Cooldown?>
	CooldownServiceUtils.validateLookup(owner, key)
	return self._registry:Observe(owner, key) :: any
end

--[=[
	Observes whether an owner/key pair currently has an active cooldown.

	@within CooldownService
	@param owner Instance
	@param key string
	@return Observable<boolean>
]=]
function CooldownService.ObserveIsOnCooldown(
	self: CooldownService,
	owner: Instance,
	key: string
): Observable.Observable<boolean>
	return self:ObserveCooldown(owner, key):Pipe({
		Rx.map(function(cooldown)
			return cooldown ~= nil
		end),
		Rx.distinct() :: any,
	}) :: any
end

--[=[
	Clears the active cooldown for an owner/key pair.

	@within CooldownService
	@param owner Instance
	@param key string
	@return boolean
]=]
function CooldownService.ClearCooldown(self: CooldownService, owner: Instance, key: string): boolean
	self._burstTracker:Reset(owner, key)
	const cooldown = self:GetCooldown(owner, key)
	if not cooldown then
		return false
	end

	cooldown:Clear()
	return true
end

function CooldownService._createCooldown(
	self: CooldownService,
	owner: Instance,
	key: string,
	duration: number
): Cooldown.Cooldown
	const folder = CooldownServiceUtils.createCooldown(owner, key, duration, self._clock)
	const cooldown = self._binders.Cooldown:Get(folder) or Cooldown.new(folder, self._clock)

	self._registry:Register(cooldown :: any)
	return cooldown
end

function CooldownService.Destroy(self: CooldownService): ()
	self._maid:DoCleaning()
end

return CooldownService
