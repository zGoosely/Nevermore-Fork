--!strict
--[=[
	@class Motor6DServiceClient
]=]
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local Motor6DServiceClient = {}
Motor6DServiceClient.ServiceName = "Motor6DServiceClient"

function Motor6DServiceClient:Init(serviceBag: ServiceBag.ServiceBag)
	assert(not self._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	-- Services
	self._serviceBag:GetService(require("@game/ReplicatedStorage/Packages/TieRealmService"))

	-- Binders
	self._serviceBag:GetService(require("./Stack/Motor6DStackClient"))
	self._serviceBag:GetService(require("./Humanoid/Motor6DStackHumanoidClient"))
end

return Motor6DServiceClient
