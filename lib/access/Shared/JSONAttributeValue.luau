--!strict
--[=[
	Stores a JSON-serializable value in one Roblox attribute and exposes it as an observable value.

	@class JSONAttributeValue
]=]

const HttpService = game:GetService("HttpService")

const require = require("../../Loader").load()

const Observable = require("Observable")

local JSONAttributeValue = {}
JSONAttributeValue.ClassName = "JSONAttributeValue"
JSONAttributeValue.__index = JSONAttributeValue

export type JSONAttributeValue<T> = typeof(setmetatable(
	{} :: {
		_object: Instance,
		_attributeName: string,
		_defaultValue: T,
		Value: T,
	},
	{} :: typeof({ __index = JSONAttributeValue })
))

local function decode<T>(value: any, defaultValue: T): T
	if type(value) ~= "string" then
		return defaultValue
	end

	local success, result = pcall(function()
		return HttpService:JSONDecode(value)
	end)

	return if success then result :: T else defaultValue
end

function JSONAttributeValue.new<T>(object: Instance, attributeName: string, defaultValue: T): JSONAttributeValue<T>
	assert(typeof(object) == "Instance", "Bad object")
	assert(type(attributeName) == "string", "Bad attributeName")

	local self = setmetatable({
		_object = object,
		_attributeName = attributeName,
		_defaultValue = defaultValue,
	}, JSONAttributeValue) :: JSONAttributeValue<T>

	if object:GetAttribute(attributeName) == nil then
		self.Value = defaultValue
	end

	return self
end

function JSONAttributeValue.Observe<T>(self: JSONAttributeValue<T>): Observable.Observable<T>
	return Observable.new(function(sub)
		local connection = self._object:GetAttributeChangedSignal(self._attributeName):Connect(function()
			sub:Fire(decode(self._object:GetAttribute(self._attributeName), self._defaultValue))
		end)

		sub:Fire(decode(self._object:GetAttribute(self._attributeName), self._defaultValue))
		return connection
	end) :: any
end

function JSONAttributeValue.__index<T>(self: JSONAttributeValue<T>, index: string): any
	if index == "Value" then
		return decode(self._object:GetAttribute(self._attributeName), self._defaultValue)
	end

	return JSONAttributeValue[index]
end

function JSONAttributeValue.__newindex<T>(self: JSONAttributeValue<T>, index: string, value: any)
	if index ~= "Value" then
		error(`Cannot set JSONAttributeValue.{index}`)
	end

	self._object:SetAttribute(self._attributeName, HttpService:JSONEncode(value))
end

return JSONAttributeValue
