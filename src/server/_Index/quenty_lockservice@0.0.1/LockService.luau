--!strict
--[=[
	Coordinates non-queued, non-reentrant locks identified by an owner Instance
	and key.

	@class LockService
	@server
]=]
const AsyncSemaphore = require("@game/ReplicatedStorage/Packages/AsyncSemaphore")
const LockPermit = require("./LockPermit")
const LockServiceTypes = require("./LockServiceTypes")
const LockServiceUtils = require("./LockServiceUtils")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

type AcquireConfig = LockServiceTypes.AcquireConfig
type LockCallback = LockServiceTypes.LockCallback

type Slot = {
	Semaphore: AsyncSemaphore.AsyncSemaphore,
	Permit: LockPermit.LockPermit,
}

const LockService = {}
LockService.ServiceName = "LockService"
LockService.ServerOnly = true

export type LockService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_slotsByOwner: { [Instance]: { [string]: Slot } },
		_destroyed: boolean,
	},
	{} :: typeof({ __index = LockService })
))

function LockService.Init(self: LockService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._slotsByOwner = {}
	self._destroyed = false
end

--[=[
	Attempts to acquire an owner/key lock immediately. Returns nil when another
	permit currently holds it.

	@within LockService
	@param config AcquireConfig
	@return LockPermit?
]=]
function LockService.TryAcquire(self: LockService, config: AcquireConfig): LockPermit.LockPermit?
	assert(LockServiceUtils.isAcquireConfig(config), "Bad config")
	assert(not self._destroyed, "LockService is destroyed")

	const owner = config.Owner
	const key = config.Key
	local slots = self._slotsByOwner[owner]
	if slots and slots[key] then
		return nil
	end
	const resolvedSlots = slots or {}

	const semaphore = AsyncSemaphore.new(1)
	const semaphorePermit = semaphore:TryAcquire()
	assert(semaphorePermit, "New lock semaphore did not provide its permit")

	local permit: LockPermit.LockPermit
	permit = LockPermit.new(owner, key, config.Holder, config.Timeout, semaphorePermit, function()
		self:_removeSlot(owner, key, permit)
	end)

	if not slots then
		self._slotsByOwner[owner] = resolvedSlots
	end
	resolvedSlots[key] = {
		Semaphore = semaphore,
		Permit = permit,
	}

	return permit
end

--[=[
	Attempts to acquire a lock and run promise-returning work. Returns nil
	without invoking the callback when the lock is occupied, and releases the
	permit when the returned Promise settles.

	@within LockService
	@param config AcquireConfig
	@param callback LockCallback
	@return Promise?
]=]
function LockService.RunAsync(self: LockService, config: AcquireConfig, callback: LockCallback): Promise.Promise<any>?
	assert(LockServiceUtils.isAcquireConfig(config), "Bad config")
	assert(t.callback(callback), "Bad callback")

	const permit = self:TryAcquire(config)
	if not permit then
		return nil
	end

	const succeeded, callbackResult = pcall(callback)
	if not succeeded then
		permit:Release("CallbackFailed")
		return Promise.rejected(callbackResult)
	end
	if not (t.table(callbackResult) and Promise.isPromise(callbackResult)) then
		permit:Release("CallbackFailed")
		return Promise.rejected("LockService callback must return a Promise")
	end

	return (callbackResult :: Promise.Promise<any>):Then(function(...)
		permit:Release("Succeeded")
		return Promise.resolved(...)
	end, function(...)
		permit:Release("Failed")
		return Promise.rejected(...)
	end)
end

--[=[
	Returns whether an owner/key lock currently has an active permit.

	@within LockService
	@param owner Instance
	@param key string
	@return boolean
]=]
function LockService.IsLocked(self: LockService, owner: Instance, key: string): boolean
	assert(t.Instance(owner), "Bad owner")
	assert(LockServiceUtils.isLockKey(key), "Bad key")

	const slots = self._slotsByOwner[owner]
	return slots ~= nil and slots[key] ~= nil
end

function LockService._removeSlot(self: LockService, owner: Instance, key: string, permit: LockPermit.LockPermit): ()
	const slots = self._slotsByOwner[owner]
	const slot = if slots then slots[key] else nil
	if not slot or slot.Permit ~= permit then
		return
	end

	slots[key] = nil
	slot.Semaphore:Destroy()
	if next(slots) == nil then
		self._slotsByOwner[owner] = nil
	end
end

function LockService.Destroy(self: LockService): ()
	if self._destroyed then
		return
	end
	self._destroyed = true

	const permits: { LockPermit.LockPermit } = {}
	for _, slots in self._slotsByOwner do
		for _, slot in slots do
			table.insert(permits, slot.Permit)
		end
	end
	for _, permit in permits do
		permit:Release("ServiceDestroyed")
	end

	table.clear(self._slotsByOwner)
	self._maid:DoCleaning()
end

return LockService
