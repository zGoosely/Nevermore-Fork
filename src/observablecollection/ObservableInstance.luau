--!strict
--[=[
	A reactive wrapper around Roblox instances that allows observing property changes.

	```lua
	local padding = ObservableInstance.new("UIPadding", {
		Parent = someFrame,
		PaddingTop = UDim.new(0, 10)
	})

	-- Observe a property
	padding:Observe("PaddingTop"):Subscribe(function(value)
		print("PaddingTop changed to:", value)
	end)

	-- Get current value
	local currentPadding = padding:GetValue("PaddingTop")

	-- Set a value
	padding:SetValue("PaddingTop", UDim.new(0, 20))

	-- Get the underlying instance
	local instance = padding:GetInstance()
	```

	@class ObservableInstance
]=]

const require = require("../Loader").load()

local Maid = require('Maid')
local Observable = require('Observable')
local ObservableSubscriptionTable = require('ObservableSubscriptionTable')

local ObservableInstance = {}
ObservableInstance.ClassName = 'ObservableInstance'
ObservableInstance.__index = ObservableInstance

export type ObservableInstance = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_instance: Instance,
		_propertyObservers: ObservableSubscriptionTable.ObservableSubscriptionTable<any>,
	},
	{} :: typeof({ __index = ObservableInstance })
))

--[=[
	Creates a new ObservableInstance

	@param className string -- The class name of the instance to create
	@param properties table? -- Optional initial properties to set
	@return ObservableInstance
]=]
function ObservableInstance.new(className: string, properties: { [string]: any }?): ObservableInstance
	assert(type(className) == 'string', 'Bad className')

	local self = setmetatable({}, ObservableInstance) :: any

	self._maid = Maid.new()
	self._instance = Instance.new(className)
	self._propertyObservers = self._maid:Add(ObservableSubscriptionTable.new())

	-- Set initial properties
	if properties then
		for property, value in properties do
			(self._instance :: any)[property] = value
		end
	end

	-- Cleanup instance when destroyed
	self._maid:GiveTask(self._instance)

	return self
end

--[=[
	Creates an ObservableInstance from an existing instance

	@param instance Instance
	@return ObservableInstance
]=]
function ObservableInstance.fromInstance(instance: Instance): ObservableInstance
	assert(typeof(instance) == 'Instance', 'Bad instance')

	local self = setmetatable({}, ObservableInstance) :: any

	self._maid = Maid.new()
	self._instance = instance
	self._propertyObservers = self._maid:Add(ObservableSubscriptionTable.new())

	return self
end

--[=[
	Observes changes to a property

	@param property string
	@return Observable<any>
]=]
function ObservableInstance.Observe(self: ObservableInstance, property: string): Observable.Observable<any>
	assert(type(property) == 'string', 'Bad property')

	return self._propertyObservers:Observe(property, function(sub)
		-- Create a connection to observe property changes
		local maid = Maid.new()

		-- Emit current value immediately
		sub:Fire((self._instance :: any)[property])

		-- Watch for changes using GetPropertyChangedSignal
		local success, signal = pcall(function()
			return self._instance:GetPropertyChangedSignal(property)
		end)

		if success and signal then
			maid:GiveTask(signal:Connect(function()
				sub:Fire((self._instance :: any)[property])
			end))
		else
			warn(`[ObservableInstance] Cannot observe property '{property}' on {self._instance.ClassName}`)
		end

		return maid
	end) :: any
end

--[=[
	Gets the current value of a property

	@param property string
	@return any
]=]
function ObservableInstance.GetValue(self: ObservableInstance, property: string): any
	assert(type(property) == 'string', 'Bad property')
	return (self._instance :: any)[property]
end

--[=[
	Sets the value of a property

	@param property string
	@param value any
]=]
function ObservableInstance.SetValue(self: ObservableInstance, property: string, value: any)
	assert(type(property) == 'string', 'Bad property')

	local hasProperty = pcall(function()
		return self._instance[property]
	end)

	if hasProperty then
		self._instance[property] = value
	end

	-- Fire observers
	self._propertyObservers:Fire(property, value)
end

--[=[
	Gets the underlying Roblox instance

	@return Instance
]=]
function ObservableInstance.GetInstance(self: ObservableInstance): Instance
	return self._instance
end

--[=[
	Sets multiple properties at once

	@param properties table
]=]
function ObservableInstance.SetProperties(self: ObservableInstance, properties: { [string]: any })
	assert(type(properties) == 'table', 'Bad properties')

	for property, value in properties do
		self:SetValue(property, value)
	end
end

--[=[
	Observes multiple properties and returns them as a table

	@param properties string[]
	@return Observable<{ [string]: any }>
]=]
function ObservableInstance.ObserveProperties(
	self: ObservableInstance,
	properties: { string }
): Observable.Observable<{ [string]: any }>
	assert(type(properties) == 'table', 'Bad properties')

	return Observable.new(function(sub)
		local maid = Maid.new()
		local currentValues = {}

		-- Initialize current values
		for _, property in properties do
			currentValues[property] = self:GetValue(property)
		end

		-- Emit initial values
		sub:Fire(table.clone(currentValues))

		-- Observe each property
		for _, property in properties do
			maid:GiveTask(self:Observe(property):Subscribe(function(value)
				currentValues[property] = value
				sub:Fire(table.clone(currentValues))
			end))
		end

		return maid
	end)
end

--[=[
	Destroys the ObservableInstance and cleans up the underlying instance
]=]
function ObservableInstance.Destroy(self: ObservableInstance)
	self._maid:Destroy()
	setmetatable(self :: any, nil)
end

return ObservableInstance
