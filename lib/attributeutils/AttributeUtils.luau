--!strict
--[=[
	Provides utility functions to work with attributes in Roblox
	@class AttributeUtils
]=]

local RunService = game:GetService('RunService')
const require = require("../Loader").load()

local CancelToken = require('CancelToken')
local Maid = require('Maid')
local Promise = require('Promise')

local DEFAULT_PREDICATE = function(value)
	return value ~= nil
end

-- Roblox rejects attribute names outside this shape, and reserves the RBX prefix
local ATTRIBUTE_NAME_PATTERN = '^[%w_]+$'
local ATTRIBUTE_NAME_MAX_LENGTH = 100
local RESERVED_ATTRIBUTE_PREFIX = 'RBX'

local AttributeUtils = {}

type ValidAttributeMap = { [string]: true }

local VALID_ATTRIBUTE_TYPES: ValidAttributeMap = table.freeze({
	['nil'] = true,
	['string'] = true,
	['boolean'] = true,
	['number'] = true,
	['UDim'] = true,
	['UDim2'] = true,
	['BrickColor'] = true,
	['CFrame'] = true,
	['Color3'] = true,
	['Vector2'] = true,
	['Vector3'] = true,
	['NumberSequence'] = true,
	['ColorSequence'] = true,
	['IntValue'] = true,
	['NumberRange'] = true,
	['Rect'] = true,
	['Font'] = true,
	['EnumItem'] = true,
} :: ValidAttributeMap)

--[=[
	Returns whether the attribute is a valid type or not for an attribute.

	```lua
	print(AttributeUtils.isValidAttributeType(typeof("hi"))) --> true
	```

	@param valueType string
	@return boolean
]=]
function AttributeUtils.isValidAttributeType(valueType: string): boolean
	return VALID_ATTRIBUTE_TYPES[valueType] == true
end

--[=[
	Returns whether Roblox will accept this string as an attribute name.

	```lua
	print(AttributeUtils.isValidAttributeName('Health')) --> true
	print(AttributeUtils.isValidAttributeName('Stats.Health')) --> false
	```

	@param attributeName string
	@return boolean
]=]
function AttributeUtils.isValidAttributeName(attributeName: string): boolean
	return #attributeName <= ATTRIBUTE_NAME_MAX_LENGTH
		and string.match(attributeName, ATTRIBUTE_NAME_PATTERN) ~= nil
		and string.sub(attributeName, 1, #RESERVED_ATTRIBUTE_PREFIX) ~= RESERVED_ATTRIBUTE_PREFIX
end

--[=[
	Sets an attribute, but only if Roblox can actually hold the value -- an
	invalid name or value type warns and returns false instead of throwing.
	Passing nil clears the attribute.

	@param instance Instance
	@param attributeName string
	@param value any
	@return boolean -- Whether the attribute was set
]=]
function AttributeUtils.setAttribute(instance: Instance, attributeName: string, value: any): boolean
	assert(typeof(instance) == 'Instance', 'Bad instance')
	assert(typeof(attributeName) == 'string', 'Bad attributeName')

	if not AttributeUtils.isValidAttributeName(attributeName) then
		warn(string.format('[AttributeUtils] - %q is not a valid attribute name', attributeName))
		return false
	end

	if not AttributeUtils.isValidAttributeType(typeof(value)) then
		warn(
			string.format(
				'[AttributeUtils] - Cannot set attribute %q to a %s, which is not a valid attribute type',
				attributeName,
				typeof(value)
			)
		)
		return false
	end

	instance:SetAttribute(attributeName, value)
	return true
end

--[=[
	Promises attribute value fits predicate

	@param instance Instance
	@param attributeName string
	@param predicate function | nil
	@param cancelToken CancelToken
	@return Promise<unknown>
]=]
function AttributeUtils.promiseAttribute(
	instance: Instance,
	attributeName: string,
	predicate,
	cancelToken: CancelToken.CancelToken?
): Promise.Promise<unknown>
	assert(typeof(instance) == 'Instance', 'Bad instance')
	assert(type(attributeName) == 'string', 'Bad attributeName')
	assert(CancelToken.isCancelToken(cancelToken) or cancelToken == nil, 'Bad cancelToken')

	predicate = predicate or DEFAULT_PREDICATE

	do
		local attributeValue = instance:GetAttribute(attributeName)
		if predicate(attributeValue) then
			return Promise.resolved(attributeValue)
		end
	end

	local promise = Promise.new()
	local maid = Maid.new()
	maid:GiveTask(promise)

	if cancelToken then
		maid:GiveTask(cancelToken.Cancelled:Connect(function()
			promise:Reject()
		end))
	end

	maid:GiveTask(instance:GetAttributeChangedSignal(attributeName):Connect(function()
		local attributeValue = instance:GetAttribute(attributeName)
		if predicate(attributeValue) then
			promise:Resolve(attributeValue)
		end
	end))

	promise:Finally(function()
		maid:DoCleaning()
	end)

	return promise
end

--[=[
	Whenever the attribute is true, the binder will be bound, and when the
	binder is bound, the attribute will be true.

	@param instance Instance
	@param attributeName string
	@param binder Binder<T>
	@return Maid
]=]
function AttributeUtils.bindToBinder(instance: Instance, attributeName: string, binder): Maid.Maid
	assert(binder, 'Bad binder')
	assert(typeof(instance) == 'Instance', 'Bad instance')
	assert(type(attributeName) == 'string', 'Bad attributeName')

	local maid = Maid.new()

	local function syncAttribute()
		if instance:GetAttribute(attributeName) then
			if RunService:IsClient() then
				binder:BindClient(instance)
			else
				binder:Bind(instance)
			end
		else
			if RunService:IsClient() then
				binder:UnbindClient(instance)
			else
				binder:Unbind(instance)
			end
		end
	end
	maid:GiveTask(instance:GetAttributeChangedSignal(attributeName):Connect(syncAttribute))

	local function syncBoundClass()
		if binder:Get(instance) then
			instance:SetAttribute(attributeName, true)
		else
			instance:SetAttribute(attributeName, false)
		end
	end
	maid:GiveTask(binder:ObserveInstance(instance, syncBoundClass))

	if binder:Get(instance) or instance:GetAttribute(attributeName) then
		instance:SetAttribute(attributeName, true)
		if RunService:IsClient() then
			binder:BindClient(instance)
		else
			binder:Bind(instance)
		end
	else
		instance:SetAttribute(attributeName, false)
		-- no need to bind
	end

	-- Depopuplate the attribute on exit
	maid:GiveTask(function()
		-- Force all cleaning first
		maid:DoCleaning()

		-- Cleanup
		instance:SetAttribute(attributeName, nil)
	end)

	return maid
end

--[=[
	Initializes an attribute for a given instance

	@param instance Instance
	@param attributeName string
	@param default any
	@return any? -- The value of the attribute
]=]
function AttributeUtils.initAttribute(instance: Instance, attributeName: string, default: any): any
	assert(typeof(instance) == 'Instance', 'Bad instance')
	assert(typeof(attributeName) == 'string', 'Bad attributeName')

	local value = instance:GetAttribute(attributeName)
	if value == nil then
		instance:SetAttribute(attributeName, default)
		value = default
	end
	return value
end

--[=[
	Retrieves an attribute, and if it is nil, returns the default
	instead.
	@param instance Instance
	@param attributeName string
	@param default T?
	@return T?
]=]
function AttributeUtils.getAttribute(instance: Instance, attributeName: string, default: any): any
	local value = instance:GetAttribute(attributeName)
	if value == nil then
		return default
	end

	return value
end

--[=[
	Removes all attributes from an instance.

	@param instance Instance
]=]
function AttributeUtils.removeAllAttributes(instance: Instance)
	assert(typeof(instance) == 'Instance', 'Bad instance')

	for key, _ in instance:GetAttributes() do
		instance:SetAttribute(key, nil)
	end
end

return AttributeUtils
