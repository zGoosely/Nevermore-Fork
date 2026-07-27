--!strict

--[=[
	Promise-based utilities for working with Roblox instances.
	Provides async operations for waiting on children, descendants, attributes, and more.

	@class PromiseInstanceUtils
]=]

const require = require("../../Loader").load()

local Promise = require("Promise")

local PromiseInstanceUtils = {}

--[=[
	Waits for a child of a specific class to be added to a parent.
	Resolves immediately if the child already exists.

	@param parent Instance -- The parent to search in
	@param className string -- The class name to search for
	@param timeout number? -- Optional timeout in seconds
	@return Promise<Instance> -- Promise that resolves with the found instance
]=]
function PromiseInstanceUtils.promiseChildOfClass(parent: Instance, className: string, timeout: number?)
	return Promise.new(function(resolve, reject)
		local instance = parent:FindFirstChildOfClass(className)
		if instance then
			resolve(instance)
			return
		end

		local connection
		connection = parent.ChildAdded:Connect(function(child)
			if child:IsA(className) then
				connection:Disconnect()
				resolve(child)
			end
		end)

		if timeout then
			task.delay(timeout, function()
				if connection.Connected then
					connection:Disconnect()
					reject(`Timeout waiting for {className}`)
				end
			end)
		end
	end)
end

--[=[
	Waits for a descendant of a specific class to be added to a parent.
	Resolves immediately if the descendant already exists.

	@param parent Instance -- The parent to search in
	@param className string -- The class name to search for
	@param timeout number? -- Optional timeout in seconds
	@return Promise<Instance> -- Promise that resolves with the found instance
]=]
function PromiseInstanceUtils.promiseDescendantOfClass(parent: Instance, className: string, timeout: number?)
	return Promise.new(function(resolve, reject)
		local found = parent:FindFirstChildOfClass(className, true)
		if found then
			resolve(found)
			return
		end

		local connection
		connection = parent.DescendantAdded:Connect(function(desc)
			if desc:IsA(className) then
				connection:Disconnect()
				resolve(desc)
			end
		end)

		if timeout then
			task.delay(timeout, function()
				if connection.Connected then
					connection:Disconnect()
					reject(`Timeout waiting for descendant {className}`)
				end
			end)
		end
	end)
end

--[=[
	Waits for a child with a specific name to be added to a parent.
	Resolves immediately if the child already exists.

	@param parent Instance -- The parent to search in
	@param name string -- The name to search for
	@param timeout number? -- Optional timeout in seconds
	@return Promise<Instance> -- Promise that resolves with the found instance
]=]
function PromiseInstanceUtils.promiseChild(parent: Instance, name: string, timeout: number?)
	return Promise.new(function(resolve, reject)
		local instance = parent:FindFirstChild(name)
		if instance then
			resolve(instance)
			return
		end

		local connection
		connection = parent.ChildAdded:Connect(function(child)
			if child.Name == name then
				connection:Disconnect()
				resolve(child)
			end
		end)

		if timeout then
			task.delay(timeout, function()
				if connection.Connected then
					connection:Disconnect()
					reject(`Timeout waiting for child {name}`)
				end
			end)
		end
	end)
end

--[=[
	Waits for a descendant with a specific name to be added to a parent.
	Resolves immediately if the descendant already exists.

	@param parent Instance -- The parent to search in
	@param name string -- The name to search for
	@param timeout number? -- Optional timeout in seconds
	@return Promise<Instance> -- Promise that resolves with the found instance
]=]
function PromiseInstanceUtils.promiseDescendant(parent: Instance, name: string, timeout: number?)
	return Promise.new(function(resolve, reject)
		local found = parent:FindFirstChild(name, true)
		if found then
			resolve(found)
			return
		end

		local connection
		connection = parent.DescendantAdded:Connect(function(desc)
			if desc.Name == name then
				connection:Disconnect()
				resolve(desc)
			end
		end)

		if timeout then
			task.delay(timeout, function()
				if connection.Connected then
					connection:Disconnect()
					reject(`Timeout waiting for descendant {name}`)
				end
			end)
		end
	end)
end

--[=[
	Waits for a child with a specific class and name to be added to a parent.
	Resolves immediately if the child already exists.

	@param parent Instance -- The parent to search in
	@param className string -- The class name to search for
	@param name string -- The name to search for
	@param timeout number? -- Optional timeout in seconds
	@return Promise<Instance> -- Promise that resolves with the found instance
]=]
function PromiseInstanceUtils.promiseChildOfClassWithName(
	parent: Instance,
	className: string,
	name: string,
	timeout: number?
)
	return Promise.new(function(resolve, reject)
		local instance = parent:FindFirstChild(name)
		if instance and instance:IsA(className) then
			resolve(instance)
			return
		end

		local connection
		connection = parent.ChildAdded:Connect(function(child)
			if child.Name == name and child:IsA(className) then
				connection:Disconnect()
				resolve(child)
			end
		end)

		if timeout then
			task.delay(timeout, function()
				if connection.Connected then
					connection:Disconnect()
					reject(`Timeout waiting for {className} named {name}`)
				end
			end)
		end
	end)
end

--[=[
	Waits for a descendant with a specific class and name to be added to a parent.
	Resolves immediately if the descendant already exists.

	@param parent Instance -- The parent to search in
	@param className string -- The class name to search for
	@param name string -- The name to search for
	@param timeout number? -- Optional timeout in seconds
	@return Promise<Instance> -- Promise that resolves with the found instance
]=]
function PromiseInstanceUtils.promiseDescendantOfClassWithName(
	parent: Instance,
	className: string,
	name: string,
	timeout: number?
)
	return Promise.new(function(resolve, reject)
		local found = parent:FindFirstChild(name, true)
		if found and found:IsA(className) then
			resolve(found)
			return
		end

		local connection
		connection = parent.DescendantAdded:Connect(function(desc)
			if desc.Name == name and desc:IsA(className) then
				connection:Disconnect()
				resolve(desc)
			end
		end)

		if timeout then
			task.delay(timeout, function()
				if connection.Connected then
					connection:Disconnect()
					reject(`Timeout waiting for descendant {className} named {name}`)
				end
			end)
		end
	end)
end

--[=[
	Waits for an attribute to be set on an instance.
	Resolves immediately if the attribute already exists.

	@param instance Instance -- The instance to watch
	@param attributeName string -- The attribute name to wait for
	@param timeout number? -- Optional timeout in seconds
	@return Promise<any> -- Promise that resolves with the attribute value
]=]
function PromiseInstanceUtils.promiseAttribute(instance: Instance, attributeName: string, timeout: number?)
	return Promise.new(function(resolve, reject)
		local value = instance:GetAttribute(attributeName)
		if value ~= nil then
			resolve(value)
			return
		end

		local connection
		connection = instance:GetAttributeChangedSignal(attributeName):Connect(function()
			local newValue = instance:GetAttribute(attributeName)
			if newValue ~= nil then
				connection:Disconnect()
				resolve(newValue)
			end
		end)

		if timeout then
			task.delay(timeout, function()
				if connection.Connected then
					connection:Disconnect()
					reject(`Timeout waiting for attribute {attributeName}`)
				end
			end)
		end
	end)
end

--[=[
	Waits for a property to reach a specific value.
	Resolves immediately if the property already has the target value.

	@param instance Instance -- The instance to watch
	@param propertyName string -- The property name to watch
	@param targetValue any -- The value to wait for
	@param timeout number? -- Optional timeout in seconds
	@return Promise<any> -- Promise that resolves with the property value
]=]
function PromiseInstanceUtils.promisePropertyValue(
	instance: Instance,
	propertyName: string,
	targetValue: any,
	timeout: number?
)
	return Promise.new(function(resolve, reject)
		local currentValue = (instance :: any)[propertyName]
		if currentValue == targetValue then
			resolve(currentValue)
			return
		end

		local connection
		connection = instance:GetPropertyChangedSignal(propertyName):Connect(function()
			local newValue = (instance :: any)[propertyName]
			if newValue == targetValue then
				connection:Disconnect()
				resolve(newValue)
			end
		end)

		if timeout then
			task.delay(timeout, function()
				if connection.Connected then
					connection:Disconnect()
					reject(`Timeout waiting for {propertyName} to be {targetValue}`)
				end
			end)
		end
	end)
end

--[=[
	Waits for an instance to be removed from the DataModel.

	@param instance Instance -- The instance to watch
	@param timeout number? -- Optional timeout in seconds
	@return Promise<void> -- Promise that resolves when the instance is removed
]=]
function PromiseInstanceUtils.promiseRemoved(instance: Instance, timeout: number?)
	return Promise.new(function(resolve, reject)
		if not instance:IsDescendantOf(game) then
			resolve()
			return
		end

		local connection
		connection = instance.AncestryChanged:Connect(function()
			if not instance:IsDescendantOf(game) then
				connection:Disconnect()
				resolve()
			end
		end)

		if timeout then
			task.delay(timeout, function()
				if connection.Connected then
					connection:Disconnect()
					reject(`Timeout waiting for instance to be removed`)
				end
			end)
		end
	end)
end

--[=[
	Waits for an instance to be parented to the DataModel.

	@param instance Instance -- The instance to watch
	@param timeout number? -- Optional timeout in seconds
	@return Promise<void> -- Promise that resolves when the instance is added
]=]
function PromiseInstanceUtils.promiseAdded(instance: Instance, timeout: number?)
	return Promise.new(function(resolve, reject)
		if instance:IsDescendantOf(game) then
			resolve()
			return
		end

		local connection
		connection = instance.AncestryChanged:Connect(function()
			if instance:IsDescendantOf(game) then
				connection:Disconnect()
				resolve()
			end
		end)

		if timeout then
			task.delay(timeout, function()
				if connection.Connected then
					connection:Disconnect()
					reject(`Timeout waiting for instance to be added`)
				end
			end)
		end
	end)
end

return PromiseInstanceUtils
