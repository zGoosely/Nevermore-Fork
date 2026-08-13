--!strict
--[=[
	@class RagdollableBase
]=]
local BaseObject = require("@game/ReplicatedStorage/Packages/BaseObject")
local Observable = require("@game/ReplicatedStorage/Packages/Observable")
local Rx = require("@game/ReplicatedStorage/Packages/Rx")
local RxSignal = require("@game/ReplicatedStorage/Packages/RxSignal")

local RagdollableBase = setmetatable({}, BaseObject)
RagdollableBase.ClassName = "RagdollableBase"
RagdollableBase.__index = RagdollableBase

export type RagdollableBase =
	typeof(setmetatable(
		{} :: {
			Ragdolled: RxSignal.RxSignal<boolean>,
			Unragdolled: RxSignal.RxSignal<boolean>,
		},
		{} :: typeof({ __index = RagdollableBase })
	))
	& BaseObject.BaseObject

function RagdollableBase.new(humanoid: Humanoid): RagdollableBase
	local self: RagdollableBase = setmetatable(BaseObject.new(humanoid) :: any, RagdollableBase)

	self.Ragdolled = RxSignal.new(function(): any
		return (self:ObserveIsRagdolled() :: any):Pipe({
			Rx.skip(1),
			Rx.where(function(value): any
				return value == true
			end),
		})
	end) :: any

	self.Unragdolled = RxSignal.new(function(): any
		return (self:ObserveIsRagdolled() :: any):Pipe({
			Rx.skip(1),
			Rx.where(function(value): any
				return value == true
			end),
		})
	end) :: any

	return self
end

function RagdollableBase.Ragdoll(self: RagdollableBase): ()
	(self._obj :: Instance):AddTag("Ragdoll")
end

function RagdollableBase.Unragdoll(self: RagdollableBase): ()
	(self._obj :: Instance):RemoveTag("Ragdoll")
end

function RagdollableBase.ObserveIsRagdolled(_self: RagdollableBase): Observable.Observable<boolean>
	return error("Not implemented")
end

function RagdollableBase.IsRagdolled(self: RagdollableBase): boolean
	return (self._obj :: Instance):HasTag("Ragdoll")
end

return RagdollableBase
