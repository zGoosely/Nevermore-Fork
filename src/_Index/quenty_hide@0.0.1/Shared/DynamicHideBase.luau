--!strict
--[=[
    @class DynamicHideBase
]=]
local BaseObject = require("@game/ReplicatedStorage/Packages/BaseObject")
local Brio = require("@game/ReplicatedStorage/Packages/Brio")
local HideUtils = require("./HideUtils")
local Observable = require("@game/ReplicatedStorage/Packages/Observable")
local RxBrioUtils = require("@game/ReplicatedStorage/Packages/RxBrioUtils")
local RxInstanceUtils = require("@game/ReplicatedStorage/Packages/RxInstanceUtils")

local DynamicHideBase = setmetatable({}, BaseObject)
DynamicHideBase.ClassName = "DynamicHideBase"
DynamicHideBase.__index = DynamicHideBase

export type DynamicHideBase =
	typeof(setmetatable(
		{} :: {
			_obj: Instance,
		},
		{} :: typeof({ __index = DynamicHideBase })
	))
	& BaseObject.BaseObject

function DynamicHideBase.new(instance: Instance): DynamicHideBase
	local self: DynamicHideBase = setmetatable(BaseObject.new(instance) :: any, DynamicHideBase)

	return self
end

function DynamicHideBase._observeHideChildrenBrio(
	self: DynamicHideBase,
	hideBinder: any
): Observable.Observable<Brio.Brio<Instance>>
	return hideBinder:ObserveBrio(self._obj):Pipe({
		RxBrioUtils.switchMapBrio(function()
			return RxInstanceUtils.observeDescendantsAndSelfBrio(self._obj, function(child)
				return HideUtils.hasLocalTransparencyModifier(child) or HideUtils.hasTransparency(child)
			end)
		end),
	})
end

return DynamicHideBase
