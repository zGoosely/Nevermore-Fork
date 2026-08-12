--!strict
--[=[
	@class RogueHumanoid
]=]

const require = require("../../Loader").load()

const PlayerHumanoidBinder = require("PlayerHumanoidBinder")
const RogueHumanoidBase = require("RogueHumanoidBase")
const RogueHumanoidInterface = require("RogueHumanoidInterface")
const ServiceBag = require("ServiceBag")

const RogueHumanoid = setmetatable({}, RogueHumanoidBase)
RogueHumanoid.ClassName = "RogueHumanoid"
RogueHumanoid.__index = RogueHumanoid

export type RogueHumanoid =
	typeof(setmetatable({} :: {}, {} :: typeof({ __index = RogueHumanoid })))
	& RogueHumanoidBase.RogueHumanoidBase

function RogueHumanoid.new(humanoid: Humanoid, serviceBag: ServiceBag.ServiceBag): RogueHumanoid
	const self: RogueHumanoid = setmetatable(RogueHumanoidBase.new(humanoid, serviceBag) :: any, RogueHumanoid)
	self._maid:Add((RogueHumanoidInterface :: any).Server:Implement(self._obj, self))
	return self
end

return PlayerHumanoidBinder.new(
		"RogueHumanoid",
		RogueHumanoid :: any
	) :: PlayerHumanoidBinder.PlayerHumanoidBinder<RogueHumanoid>
