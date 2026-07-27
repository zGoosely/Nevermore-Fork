--!strict
--[=[
	@class BindToCloseService
]=]

local RunService = game:GetService("RunService")
const require = require("../Loader").load()

local Maid = require("Maid")
local Promise = require("Promise")
local ServiceBag = require("ServiceBag")
local Symbol = require("Symbol")
local t = require("t")

local BindToCloseService = {}
BindToCloseService.ServiceName = "BindToCloseService"

export type BindToCloseService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_subscriptions: { [typeof(Symbol.named())]: () -> any },
	},
	{} :: typeof({ __index = BindToCloseService })
))

function BindToCloseService.Init(self: BindToCloseService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	self._subscriptions = {}
end

function BindToCloseService.Start(self: BindToCloseService)
	if RunService:IsServer() then
		game:BindToClose(function()
			local ok, err = self:_promiseClose():Yield()
			if not ok then
				warn(`BindToCloseService - Failed to close all: {err}`)
			end
		end)
	else
		self._maid:Add(function()
			self:_promiseClose()
		end)
	end
end

--[=[
	Binds the promise to call on close. Can be unregistered

	@param saveCallback function
	@return function -- Call to unregister callback
]=]
function BindToCloseService.RegisterPromiseOnCloseCallback(self: BindToCloseService, saveCallback: () -> ())
	assert(t.callback(saveCallback), "Bad saveCallback")

	local id = Symbol.named("savingCallbackId")
	self._subscriptions[id] = saveCallback

	return function()
		self._subscriptions[id] = nil
	end
end

function BindToCloseService._promiseClose(self: BindToCloseService): Promise.Promise<any>
	local promises = {}

	for _, caller in self._subscriptions do
		local promise = caller()
		if Promise.isPromise(promise) then
			table.insert(promises, promise)
		else
			warn(`[BindToCloseService] - Bad promise returned from close callback.`)
		end
	end

	return Promise.all(promises)
end

function BindToCloseService.Destroy(self: BindToCloseService)
	self._maid:DoCleaning()
end

return BindToCloseService
