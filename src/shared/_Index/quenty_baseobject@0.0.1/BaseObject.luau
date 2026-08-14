--!strict
--[=[
	Provides a common maid, optional referenced object, and destruction lifecycle for stateful classes.

	@class BaseObject
]=]
const Maid = require("@game/ReplicatedStorage/Packages/Maid")

const BaseObject = {}
BaseObject.ClassName = "BaseObject"
BaseObject.__index = BaseObject

export type BaseObject<T> = {
	_obj: T?,
	_maid: Maid.Maid,
	Destroy: (self: BaseObject<T>) -> (),
}

function BaseObject.new<T>(obj: T?): any
	-- Subclasses replace this metatable and add required fields before casting to their concrete type.
	return setmetatable({
		_maid = Maid.new(),
		_obj = obj :: T?,
	}, BaseObject)
end

function BaseObject.Destroy<T>(self: BaseObject<T>): ()
	self._maid:DoCleaning()
	setmetatable(self :: any, nil)
end

return BaseObject
