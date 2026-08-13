--!strict
--[=[
	Owns a named post-processing effect and the stacks that control its properties.

	@class LightingEffect
	@client
]=]
const BaseObject = require("@game/ReplicatedStorage/Packages/BaseObject")
const StateStack = require("@game/ReplicatedStorage/Packages/StateStack")
const t = require("@game/ReplicatedStorage/Packages/t")

const Lighting = game:GetService("Lighting")

const LightingEffect = setmetatable({}, BaseObject)
LightingEffect.ClassName = "LightingEffect"
LightingEffect.__index = LightingEffect

export type LightingEffect =
	typeof(setmetatable(
		{} :: {
			_effect: PostEffect,
			_name: string,
			_className: string,
			_propertyStacks: { [string]: StateStack.StateStack<any> },
		},
		{} :: typeof({ __index = LightingEffect })
	))
	& BaseObject.BaseObject<PostEffect>

function LightingEffect.new(name: string, className: string): LightingEffect
	assert(t.string(name) and name ~= "", "Bad name")
	assert(t.string(className) and className ~= "", "Bad className")

	const effect = Instance.new(className)
	if not t.instanceIsA("PostEffect")(effect) then
		effect:Destroy()
		error(string.format("className %q is not a PostEffect", className))
	end

	effect.Name = name
	effect.Parent = Lighting

	const self: LightingEffect = setmetatable(BaseObject.new(effect) :: any, LightingEffect)
	self._effect = effect
	self._name = name
	self._className = className
	self._propertyStacks = {}

	return self
end

--[=[
	Returns the effect's configured name.

	@within LightingEffect
	@return string
]=]
function LightingEffect.GetName(self: LightingEffect): string
	return self._name
end

--[=[
	Returns the Roblox class name used by this effect.

	@within LightingEffect
	@return string
]=]
function LightingEffect.GetClassName(self: LightingEffect): string
	return self._className
end

--[=[
	Returns the owned post-processing Instance.

	@within LightingEffect
	@return PostEffect
]=]
function LightingEffect.GetInstance(self: LightingEffect): PostEffect
	return self._effect
end

--[=[
	Returns the stack controlling a property, capturing its current value as the
	baseline the first time the property is requested.

	@within LightingEffect
	@param propertyName string
	@return StateStack
]=]
function LightingEffect.GetPropertyStack<T>(self: LightingEffect, propertyName: string): StateStack.StateStack<T>
	assert(t.string(propertyName) and propertyName ~= "", "Bad propertyName")

	const existing = self._propertyStacks[propertyName]
	if existing then
		return existing :: StateStack.StateStack<T>
	end

	const success, defaultValue = pcall(function(): any
		return (self._effect :: any)[propertyName]
	end)
	assert(success and defaultValue ~= nil, string.format("Unknown property %q", propertyName))

	const propertyStack = self._maid:Add(StateStack.new(defaultValue, typeof(defaultValue)))
	self._propertyStacks[propertyName] = propertyStack

	self._maid:GiveTask(propertyStack:Observe():Subscribe(function(value: T)
		(self._effect :: any)[propertyName] = value
	end))

	return propertyStack
end

--[=[
	Pushes a property override and returns a cleanup function that removes it.

	@within LightingEffect
	@param propertyName string
	@param value T
	@return function
]=]
function LightingEffect.PushProperty<T>(self: LightingEffect, propertyName: string, value: T): () -> ()
	return self:GetPropertyStack(propertyName):PushState(value)
end

return LightingEffect
