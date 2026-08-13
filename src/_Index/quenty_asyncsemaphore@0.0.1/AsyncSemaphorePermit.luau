--!strict
--[=[
	Represents one acquired [AsyncSemaphore] permit. Releasing a permit is
	idempotent, and the permit may be given directly to a [Maid].

	@class AsyncSemaphorePermit
]=]
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const t = require("@game/ReplicatedStorage/Packages/t")

const AsyncSemaphorePermit = {}
AsyncSemaphorePermit.ClassName = "AsyncSemaphorePermit"
AsyncSemaphorePermit.__index = AsyncSemaphorePermit

export type AsyncSemaphorePermit = typeof(setmetatable(
	{} :: {
		_isReleased: boolean,
		_maid: Maid.Maid,
	},
	{} :: typeof({ __index = AsyncSemaphorePermit })
))

function AsyncSemaphorePermit.new(releaseCallback: () -> ()): AsyncSemaphorePermit
	assert(t.callback(releaseCallback), "Bad releaseCallback")

	const self = setmetatable({}, AsyncSemaphorePermit) :: AsyncSemaphorePermit

	self._isReleased = false
	self._maid = Maid.new()
	self._maid:Add(releaseCallback)

	return self
end

--[=[
	Releases the permit. Subsequent calls do nothing.

	@within AsyncSemaphorePermit
]=]
function AsyncSemaphorePermit.Release(self: AsyncSemaphorePermit): ()
	if self._isReleased then
		return
	end
	self._isReleased = true

	self._maid:DoCleaning()
end

--[=[
	Returns whether the permit has already been released.

	@within AsyncSemaphorePermit
	@return boolean
]=]
function AsyncSemaphorePermit.IsReleased(self: AsyncSemaphorePermit): boolean
	return self._isReleased
end

function AsyncSemaphorePermit.Destroy(self: AsyncSemaphorePermit): ()
	self:Release()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return AsyncSemaphorePermit
