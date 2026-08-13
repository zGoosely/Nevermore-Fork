--!strict
--[=[
	Represents exclusive ownership of one owner/key lock until explicit release,
	timeout, or owner/holder destruction.

	@class LockPermit
	@server
]=]
const AsyncSemaphorePermit = require("@game/ReplicatedStorage/Packages/AsyncSemaphorePermit")
const LockServiceUtils = require("./LockServiceUtils")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Signal = require("@game/ReplicatedStorage/Packages/Signal")
const t = require("@game/ReplicatedStorage/Packages/t")

export type ReleaseCallback = () -> ()

const DEFAULT_RELEASE_REASON = "Released"
const DESTROYED_REASON = "Destroyed"
const HOLDER_DESTROYED_REASON = "HolderDestroyed"
const OWNER_DESTROYED_REASON = "OwnerDestroyed"
const TIMEOUT_REASON = "Timeout"

const LockPermit = {}
LockPermit.ClassName = "LockPermit"
LockPermit.__index = LockPermit

export type LockPermit = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_owner: Instance,
		_key: string,
		_holder: Instance?,
		_semaphorePermit: AsyncSemaphorePermit.AsyncSemaphorePermit,
		_releaseCallback: ReleaseCallback,
		_isReleased: boolean,
		_releaseReason: string?,
		_destroyed: boolean,
		Released: Signal.Signal<string>,
	},
	{} :: typeof({ __index = LockPermit })
))

function LockPermit.new(
	owner: Instance,
	key: string,
	holder: Instance?,
	timeout: number,
	semaphorePermit: AsyncSemaphorePermit.AsyncSemaphorePermit,
	releaseCallback: ReleaseCallback
): LockPermit
	assert(t.Instance(owner), "Bad owner")
	assert(LockServiceUtils.isLockKey(key), "Bad key")
	assert(t.optional(t.Instance)(holder), "Bad holder")
	assert(LockServiceUtils.isTimeout(timeout), "Bad timeout")
	assert(t.table(semaphorePermit), "Bad semaphorePermit")
	assert(t.callback(releaseCallback), "Bad releaseCallback")

	const self = setmetatable({}, LockPermit) :: LockPermit
	self._maid = Maid.new()
	self._owner = owner
	self._key = key
	self._holder = holder
	self._semaphorePermit = semaphorePermit
	self._releaseCallback = releaseCallback
	self._isReleased = false
	self._releaseReason = nil
	self._destroyed = false
	self.Released = Signal.new()

	self._maid:Add(semaphorePermit)
	self._maid:Add(owner.Destroying:Connect(function()
		self:Release(OWNER_DESTROYED_REASON)
	end))
	if holder and holder ~= owner then
		self._maid:Add(holder.Destroying:Connect(function()
			self:Release(HOLDER_DESTROYED_REASON)
		end))
	end
	self._maid:Add(task.delay(timeout, function()
		self:Release(TIMEOUT_REASON)
	end))

	return self
end

--[=[
	Returns the Instance whose namespace contains this lock.

	@within LockPermit
	@return Instance
]=]
function LockPermit.GetOwner(self: LockPermit): Instance
	return self._owner
end

--[=[
	Returns the lock key within the owner namespace.

	@within LockPermit
	@return string
]=]
function LockPermit.GetKey(self: LockPermit): string
	return self._key
end

--[=[
	Returns the optional Instance identified as the current holder.

	@within LockPermit
	@return Instance?
]=]
function LockPermit.GetHolder(self: LockPermit): Instance?
	return self._holder
end

--[=[
	Returns whether this permit has released its lock.

	@within LockPermit
	@return boolean
]=]
function LockPermit.IsReleased(self: LockPermit): boolean
	return self._isReleased
end

--[=[
	Returns the first release reason, or nil while held.

	@within LockPermit
	@return string?
]=]
function LockPermit.GetReleaseReason(self: LockPermit): string?
	return self._releaseReason
end

--[=[
	Releases the lock once and returns whether this call performed the release.

	@within LockPermit
	@param reason string?
	@return boolean
]=]
function LockPermit.Release(self: LockPermit, reason: string?): boolean
	assert(t.optional(t.string)(reason), "Bad reason")
	assert(reason == nil or LockServiceUtils.isReason(reason), "Bad reason")

	if self._isReleased then
		return false
	end

	self._isReleased = true
	self._releaseReason = reason or DEFAULT_RELEASE_REASON
	self.Released:Fire(self._releaseReason)
	self._maid:DoCleaning()
	self._releaseCallback()
	self.Released:Destroy()

	return true
end

function LockPermit.Destroy(self: LockPermit): ()
	if self._destroyed then
		return
	end
	self._destroyed = true

	self:Release(DESTROYED_REASON)
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return LockPermit
