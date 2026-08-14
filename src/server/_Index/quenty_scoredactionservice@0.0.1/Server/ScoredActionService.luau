--!strict
--[=[
	@class ScoredActionService
]=]
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local ScoredActionService = {}
ScoredActionService.ServiceName = "ScoredActionService"

function ScoredActionService:Init(serviceBag: ServiceBag.ServiceBag)
	assert(not self._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	-- External
	self._serviceBag:GetService(require("@game/ReplicatedStorage/Packages/InputKeyMapService"))
end

return ScoredActionService
