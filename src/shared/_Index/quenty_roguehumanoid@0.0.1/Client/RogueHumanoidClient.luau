--!strict
--[=[
	@class RogueHumanoidClient
]=]
const Binder = require("@game/ReplicatedStorage/Packages/Binder")
const RogueHumanoidBase = require("../Shared/RogueHumanoidBase")
const RogueHumanoidInterface = require("../Shared/RogueHumanoidInterface")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

const RogueHumanoidClient = setmetatable({}, RogueHumanoidBase)
RogueHumanoidClient.ClassName = "RogueHumanoidClient"
RogueHumanoidClient.__index = RogueHumanoidClient

export type RogueHumanoidClient =
	typeof(setmetatable({} :: {}, {} :: typeof({ __index = RogueHumanoidClient })))
	& RogueHumanoidBase.RogueHumanoidBase

function RogueHumanoidClient.new(humanoid: Humanoid, serviceBag: ServiceBag.ServiceBag): RogueHumanoidClient
	const self: RogueHumanoidClient =
		setmetatable(RogueHumanoidBase.new(humanoid, serviceBag) :: any, RogueHumanoidClient)
	self._maid:Add((RogueHumanoidInterface :: any).Client:Implement(self._obj, self))
	return self
end

return Binder.new("RogueHumanoid", RogueHumanoidClient :: any) :: Binder.Binder<RogueHumanoidClient>
