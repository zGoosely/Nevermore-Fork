--!strict
--[=[
	@class RogueHumanoid
]=]
const PlayerHumanoidBinder = require("@game/ReplicatedStorage/Packages/PlayerHumanoidBinder")
const RogueHumanoidBase = require("../Shared/RogueHumanoidBase")
const RogueHumanoidInterface = require("../Shared/RogueHumanoidInterface")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

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
