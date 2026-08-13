--!strict
--[=[
    @class Motor6DStackHumanoidInterface
]=]
local Brio = require("@game/ReplicatedStorage/Packages/Brio")
local Maid = require("@game/ReplicatedStorage/Packages/Maid")
local Motor6DStackInterface = require("../Stack/Motor6DStackInterface")
local Motor6DTransformer = require("../Animation/Motor6DTransformer")
local Observable = require("@game/ReplicatedStorage/Packages/Observable")
local TieDefinition = require("@game/ReplicatedStorage/Packages/TieDefinition")

export type Motor6DStackHumanoidInterface = {
	ObserveMotor6DsBrio: (self: Motor6DStackHumanoidInterface) -> Observable.Observable<Brio.Brio<Motor6D>>,
	ObserveMotor6DStacksBrio: (
		self: Motor6DStackHumanoidInterface
	) -> Observable.Observable<Brio.Brio<Motor6DStackInterface.Motor6DStackInterface>>,
	PushForEachMotor6D: (
		self: Motor6DStackHumanoidInterface,
		createTransformerCallback: CreateTransformerCallback
	) -> () -> (),
}

export type CreateTransformerCallback = (
	maid: Maid.Maid,
	motor6DStack: Motor6DStackInterface.Motor6DStackInterface
) -> Motor6DTransformer.Motor6DTransformer

return TieDefinition.new("Motor6DStackHumanoid", {
	ObserveMotor6DsBrio = TieDefinition.Types.METHOD,
	ObserveMotor6DStacksBrio = TieDefinition.Types.METHOD,
	PushForEachMotor6D = TieDefinition.Types.METHOD,
})
