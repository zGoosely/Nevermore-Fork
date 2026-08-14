--!strict

const BaseObject = require("../src/shared/_Index/quenty_baseobject@0.0.1/BaseObject")

const Example = setmetatable({}, BaseObject)
Example.ClassName = "Example"
Example.__index = Example

export type Example =
	typeof(setmetatable(
		{} :: {
			_value: number,
		},
		{} :: typeof({ __index = Example })
	))
	& BaseObject.BaseObject<number>

function Example.new(value: number): Example
	const self = setmetatable(BaseObject.new(value), Example) :: Example
	self._value = value
	return self
end

return Example
