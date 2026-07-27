--!strict
--[=[
	@class RogueHumanoidServiceClient
]=]

const require = require("../../Loader").load()

const ServiceBag = require("ServiceBag")

const RogueHumanoidServiceClient = {}
RogueHumanoidServiceClient.ServiceName = "RogueHumanoidServiceClient"

export type RogueHumanoidServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
	},
	{} :: typeof({ __index = RogueHumanoidServiceClient })
))

function RogueHumanoidServiceClient.Init(self: RogueHumanoidServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._serviceBag:GetService(require("RoguePropertyService"))
	self._serviceBag:GetService(require("RogueHumanoidClient"))
end

return RogueHumanoidServiceClient
