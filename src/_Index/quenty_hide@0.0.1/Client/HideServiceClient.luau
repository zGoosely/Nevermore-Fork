--!strict
--[=[
	@class HideServiceClient
]=]
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local HideServiceClient = {}
HideServiceClient.ServiceName = "HideServiceClient"

function HideServiceClient:Init(serviceBag: ServiceBag.ServiceBag)
	assert(not self._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	-- External
	self._serviceBag:GetService(require("@game/ReplicatedStorage/Packages/TransparencyService"))

	-- Binders
	self._serviceBag:GetService(require("./Binders/HideClient"))
	self._serviceBag:GetService(require("./Binders/DynamicHideClient"))
end

return HideServiceClient
