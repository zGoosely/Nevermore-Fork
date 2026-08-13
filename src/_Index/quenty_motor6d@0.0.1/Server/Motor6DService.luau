--!strict
--[=[
	@class Motor6DService
]=]
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local Motor6DService = {}
Motor6DService.ServiceName = "Motor6DService"

export type Motor6DService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
	},
	{} :: typeof({ __index = Motor6DService })
))

function Motor6DService.Init(self: Motor6DService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	-- Services
	self._serviceBag:GetService(require("@game/ReplicatedStorage/Packages/TieRealmService"))

	-- Binders
	self._serviceBag:GetService(require("./Stack/Motor6DStack"))
	self._serviceBag:GetService(require("./Humanoid/Motor6DStackHumanoid"))
end

return Motor6DService
