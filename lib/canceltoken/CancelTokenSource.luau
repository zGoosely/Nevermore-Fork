--!strict
--[=[
	Owns cancellation authority for a read-only [CancelToken].

	@class CancelTokenSource
]=]

const require = require("../Loader").load()

const CancelToken = require("CancelToken")
const t = require("t")

const SOURCE_DESTROYED_REASON = "SourceDestroyed"

const CancelTokenSource = {}
CancelTokenSource.ClassName = "CancelTokenSource"
CancelTokenSource.__index = CancelTokenSource

export type CancelTokenSource = typeof(setmetatable(
	{} :: {
		_cancel: CancelToken.Cancel,
		_token: CancelToken.CancelToken,
		_isDestroyed: boolean,
	},
	{} :: typeof({ __index = CancelTokenSource })
))

function CancelTokenSource.new(): CancelTokenSource
	local cancelCallback: CancelToken.Cancel? = nil
	const token = CancelToken.new(function(cancel)
		cancelCallback = cancel
	end)
	const cancel = cancelCallback
	assert(cancel, "CancelToken executor did not provide cancellation authority")

	const self = setmetatable({}, CancelTokenSource) :: CancelTokenSource
	self._cancel = cancel
	self._token = token
	self._isDestroyed = false

	return self
end

--[=[
	Returns the read-only token given to cancellable work.

	@within CancelTokenSource
	@return CancelToken
]=]
function CancelTokenSource.GetToken(self: CancelTokenSource): CancelToken.CancelToken
	return self._token
end

--[=[
	Requests cancellation once. Later calls preserve the original reason.

	@within CancelTokenSource
	@param reason string?
	@return boolean
]=]
function CancelTokenSource.Cancel(self: CancelTokenSource, reason: string?): boolean
	assert(t.optional(t.string)(reason), "Bad reason")
	assert(reason == nil or reason ~= "", "Bad reason")

	if self._token:IsCancelled() then
		return false
	end

	self._cancel(reason)
	return true
end

--[=[
	Returns whether cancellation has already been requested.

	@within CancelTokenSource
	@return boolean
]=]
function CancelTokenSource.IsCancelled(self: CancelTokenSource): boolean
	return self._token:IsCancelled()
end

function CancelTokenSource.Destroy(self: CancelTokenSource): ()
	if self._isDestroyed then
		return
	end
	self._isDestroyed = true

	self:Cancel(SOURCE_DESTROYED_REASON)
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return CancelTokenSource
