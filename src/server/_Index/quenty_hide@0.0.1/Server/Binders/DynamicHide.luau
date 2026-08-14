--!strict
--[=[
    @class DynamicHide
]=]
local Binder = require("@game/ReplicatedStorage/Packages/Binder")
local DynamicHideBase = require("../../Shared/DynamicHideBase")
local HideUtils = require("../../Shared/HideUtils")
local Maid = require("@game/ReplicatedStorage/Packages/Maid")
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local DynamicHide = setmetatable({}, DynamicHideBase)
DynamicHide.ClassName = "DynamicHide"
DynamicHide.__index = DynamicHide

export type DynamicHide =
	typeof(setmetatable(
		{} :: {
			_obj: Instance,
			_serviceBag: ServiceBag.ServiceBag,
			_hideBinder: any,
		},
		{} :: typeof({ __index = DynamicHide })
	))
	& DynamicHideBase.DynamicHideBase

function DynamicHide.new(instance: Instance, serviceBag: ServiceBag.ServiceBag): DynamicHide
	local self: DynamicHide = setmetatable(DynamicHideBase.new(instance) :: any, DynamicHide)

	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._hideBinder = self._serviceBag:GetService(require("./Hide"))

	self._maid:GiveTask(self:_observeHideChildrenBrio(self._hideBinder):Subscribe(function(childBrio)
		if childBrio:IsDead() then
			return
		end

		local childMaid, childInstance = childBrio:ToMaidAndValue()
		self:_hideChild(childMaid, childInstance)
	end))

	return self
end

function DynamicHide._hideChild(_self: DynamicHide, maid: Maid.Maid, instance: Instance)
	if HideUtils.hasLocalTransparencyModifier(instance) then
		(instance :: any).LocalTransparencyModifier = 1

		maid:GiveTask(function()
			(instance :: any).LocalTransparencyModifier = 0
		end)
	-- selene: allow(empty_if)
	elseif HideUtils.hasTransparency(instance) then
		-- Note we don't want to replicate this necessarily
	else
		error("[DynamicHide] - Bad instance for hiding")
	end
end

return Binder.new("DynamicHide", DynamicHide :: any) :: Binder.Binder<DynamicHide>
