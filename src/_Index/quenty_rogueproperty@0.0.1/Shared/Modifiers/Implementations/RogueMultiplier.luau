--!strict
--[=[
	@class RogueMultiplier
]=]
local Binder = require("@game/ReplicatedStorage/Packages/Binder")
local LinearValue = require("@game/ReplicatedStorage/Packages/LinearValue")
local Observable = require("@game/ReplicatedStorage/Packages/Observable")
local RogueModifierBase = require("./RogueModifierBase")
local RogueModifierInterface = require("../RogueModifierInterface")
local Rx = require("@game/ReplicatedStorage/Packages/Rx")
local RxInstanceUtils = require("@game/ReplicatedStorage/Packages/RxInstanceUtils")
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local RogueMultiplier = setmetatable({}, RogueModifierBase)
RogueMultiplier.ClassName = "RogueMultiplier"
RogueMultiplier.__index = RogueMultiplier

export type RogueMultiplier =
	typeof(setmetatable({} :: {}, {} :: typeof({ __index = RogueMultiplier })))
	& RogueModifierBase.RogueModifierBase

function RogueMultiplier.new(valueObject: Instance, serviceBag: ServiceBag.ServiceBag): RogueMultiplier
	local self: RogueMultiplier = setmetatable(RogueModifierBase.new(valueObject, serviceBag) :: any, RogueMultiplier)

	self._maid:GiveTask(RogueModifierInterface:Implement(self._obj :: any, self, self._tieRealmService:GetTieRealm()))

	return self
end

function RogueMultiplier.GetModifiedVersion(self: RogueMultiplier, value: any): any
	if not self._data.Enabled.Value then
		return value
	end

	local input = LinearValue.toLinearIfNeeded(value)
	local multiplier = LinearValue.toLinearIfNeeded((self._obj :: any).Value)

	return LinearValue.fromLinearIfNeeded((input :: any) * multiplier)
end

function RogueMultiplier.GetInvertedVersion(self: RogueMultiplier, value: any): any
	if not self._data.Enabled.Value then
		return value
	end

	local input = LinearValue.toLinearIfNeeded(value)
	local multiplier = LinearValue.toLinearIfNeeded((self._obj :: any).Value)

	return LinearValue.fromLinearIfNeeded((input :: any) / multiplier)
end

function RogueMultiplier.ObserveModifiedVersion(self: RogueMultiplier, inputValue: any): Observable.Observable<any>
	local combined: any = Rx.combineLatest({
		inputValue = inputValue,
		enabled = self._data.Enabled:Observe(),
		multiplier = RxInstanceUtils.observeProperty(self._obj :: any, "Value"),
	})

	return combined:Pipe({
		Rx.map(function(state): any
			if not state.enabled then
				return state.inputValue
			end

			if state.inputValue and type(state.inputValue) == type(state.multiplier) then
				local input = LinearValue.toLinearIfNeeded(state.inputValue)
				local multiplier = LinearValue.toLinearIfNeeded(state.multiplier)

				return LinearValue.fromLinearIfNeeded((input :: any) * multiplier)
			else
				return state.inputValue
			end
		end),
		Rx.distinct(),
	} :: { any })
end

return Binder.new("RogueMultiplier", RogueMultiplier :: any) :: Binder.Binder<RogueMultiplier>
