--!strict
--[=[
	@class HideService
]=]
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local HideService = {}
HideService.ServiceName = "HideService"

function HideService:Init(serviceBag: ServiceBag.ServiceBag)
	assert(not self._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	-- Binders
	self._serviceBag:GetService(require("./Binders/Hide"))
	self._serviceBag:GetService(require("./Binders/DynamicHide"))
end

return HideService
