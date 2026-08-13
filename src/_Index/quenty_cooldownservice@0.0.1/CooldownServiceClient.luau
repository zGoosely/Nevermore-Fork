--!strict
--[=[
	Queries replicated cooldowns and owns optional local client predictions.

	@class CooldownServiceClient
	@client
]=]
const CooldownBindersClient = require("./Client/CooldownBindersClient")
const CooldownClient = require("./Client/CooldownClient")
const CooldownClockService = require("./Shared/CooldownClockService")
const CooldownRegistry = require("./Shared/CooldownRegistry")
const CooldownServiceConstants = require("./Shared/CooldownServiceConstants")
const CooldownServiceTypes = require("./Shared/CooldownServiceTypes")
const CooldownServiceUtils = require("./Shared/CooldownServiceUtils")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const Rx = require("@game/ReplicatedStorage/Packages/Rx")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

type Clock = CooldownServiceTypes.Clock
type CooldownType = CooldownServiceTypes.CooldownType
type CooldownValue = CooldownServiceTypes.CooldownValue

const CooldownServiceClient = {}
CooldownServiceClient.ServiceName = "CooldownServiceClient"

export type CooldownServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_cooldownClockService: CooldownClockService.CooldownClockService,
		_binders: CooldownBindersClient.CooldownBindersClient,
		_clock: Clock,
		_registry: CooldownRegistry.CooldownRegistry,
	},
	{} :: typeof({ __index = CooldownServiceClient })
))

function CooldownServiceClient.Init(self: CooldownServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._cooldownClockService = self._serviceBag:GetService(CooldownClockService)
	self._binders = self._serviceBag:GetService(CooldownBindersClient) :: any
	self._clock = function()
		return self._cooldownClockService:GetTime()
	end
	self._registry = self._maid:Add(CooldownRegistry.new(self._binders.Cooldown :: any, self._clock, false, true))
end

--[=[
	Returns the effective active cooldown for an owner/key pair. Authoritative
	replicated state takes priority over local prediction.

	@within CooldownServiceClient
	@param owner Instance
	@param key string
	@return CooldownClient?
]=]
function CooldownServiceClient.GetCooldown(
	self: CooldownServiceClient,
	owner: Instance,
	key: string
): CooldownClient.CooldownClient?
	CooldownServiceUtils.validateLookup(owner, key)
	return self._registry:Get(owner, key) :: any
end

--[=[
	Returns whether authoritative or predicted state currently cools down an
	owner/key pair.

	@within CooldownServiceClient
	@param owner Instance
	@param key string
	@return boolean
]=]
function CooldownServiceClient.IsOnCooldown(self: CooldownServiceClient, owner: Instance, key: string): boolean
	return self:GetCooldown(owner, key) ~= nil
end

--[=[
	Returns the effective nonnegative remaining duration for an owner/key pair.

	@within CooldownServiceClient
	@param owner Instance
	@param key string
	@return number
]=]
function CooldownServiceClient.GetRemainingTime(self: CooldownServiceClient, owner: Instance, key: string): number
	const cooldown = self:GetCooldown(owner, key)
	return if cooldown then cooldown:GetRemainingTime() else 0
end

--[=[
	Observes the effective active cooldown for an owner/key pair.

	@within CooldownServiceClient
	@param owner Instance
	@param key string
	@return Observable<CooldownClient?>
]=]
function CooldownServiceClient.ObserveCooldown(
	self: CooldownServiceClient,
	owner: Instance,
	key: string
): Observable.Observable<CooldownClient.CooldownClient?>
	CooldownServiceUtils.validateLookup(owner, key)
	return self._registry:Observe(owner, key) :: any
end

--[=[
	Observes whether authoritative or predicted state currently cools down an
	owner/key pair.

	@within CooldownServiceClient
	@param owner Instance
	@param key string
	@return Observable<boolean>
]=]
function CooldownServiceClient.ObserveIsOnCooldown(
	self: CooldownServiceClient,
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
	Begins an optional local prediction when the pair is ready. The returned
	idempotent callback cancels the prediction after a server rejection.

	@within CooldownServiceClient
	@param owner Instance
	@param key string
	@param duration number
	@return () -> ()
]=]
function CooldownServiceClient.PredictCooldown(
	self: CooldownServiceClient,
	owner: Instance,
	key: string,
	duration: number
): () -> ()
	CooldownServiceUtils.validateLookup(owner, key)
	assert(CooldownServiceUtils.isDuration(duration), "Bad duration")

	if self._registry:Get(owner, key) then
		return function() end
	end

	const folder = CooldownServiceUtils.createCooldown(owner, key, duration, self._clock)
	const cooldown = self._binders.Cooldown:Get(folder) or CooldownClient.new(folder, self._clock)
	self._registry:Register(cooldown :: any)

	local isCancelled = false
	return function()
		if isCancelled then
			return
		end
		isCancelled = true

		if folder.Parent and folder:GetAttribute(CooldownServiceConstants.PREDICTED_ATTRIBUTE) == true then
			folder:Destroy()
		end
	end
end

--[=[
	Predicts the base duration of a typed cooldown. Authoritative replicated
	state replaces the prediction when a burst penalty is resolved.

	@within CooldownServiceClient
	@param owner Instance
	@param key string
	@param cooldownType CooldownType
	@param cooldownValue CooldownValue
	@return () -> ()
]=]
function CooldownServiceClient.PredictTypedCooldown(
	self: CooldownServiceClient,
	owner: Instance,
	key: string,
	cooldownType: CooldownType,
	cooldownValue: CooldownValue
): () -> ()
	const duration = CooldownServiceUtils.getBaseDuration(cooldownType, cooldownValue)
	return self:PredictCooldown(owner, key, duration)
end

function CooldownServiceClient.Destroy(self: CooldownServiceClient): ()
	self._maid:DoCleaning()
end

return CooldownServiceClient
