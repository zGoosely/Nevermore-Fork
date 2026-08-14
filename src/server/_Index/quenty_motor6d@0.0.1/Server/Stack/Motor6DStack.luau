--!strict
--[=[
	@class Motor6DStack
]=]
local Binder = require("@game/ReplicatedStorage/Packages/Binder")
local Motor6DStackBase = require("../../Shared/Stack/Motor6DStackBase")
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local Motor6DStack = setmetatable({}, Motor6DStackBase)
Motor6DStack.ClassName = "Motor6DStack"
Motor6DStack.__index = Motor6DStack

export type Motor6DStack =
	typeof(setmetatable(
		{} :: {
			_serviceBag: ServiceBag.ServiceBag,
		},
		{} :: typeof({ __index = Motor6DStack })
	))
	& Motor6DStackBase.Motor6DStackBase

function Motor6DStack.new(motor6D: Motor6D, serviceBag: ServiceBag.ServiceBag): Motor6DStack
	local self: Motor6DStack = setmetatable(Motor6DStackBase.new(motor6D, serviceBag) :: any, Motor6DStack)

	self._serviceBag = assert(serviceBag, "No serviceBag")

	return self
end

return Binder.new("Motor6DStack", Motor6DStack :: any) :: Binder.Binder<Motor6DStack>
