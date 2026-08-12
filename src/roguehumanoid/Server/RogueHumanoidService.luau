--!strict
--[=[
	@class RogueHumanoidService
]=]

const require = require("../../Loader").load()

const ServiceBag = require("ServiceBag")

const RogueHumanoidService = {}
RogueHumanoidService.ServiceName = "RogueHumanoidService"

export type RogueHumanoidService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
	},
	{} :: typeof({ __index = RogueHumanoidService })
))

function RogueHumanoidService.Init(self: RogueHumanoidService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._serviceBag:GetService(require("RoguePropertyService"))
	self._serviceBag:GetService(require("RogueHumanoid"))
end

return RogueHumanoidService
