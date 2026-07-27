--!strict
--[=[
	Utility functions involving sets, which are tables with the key as an index, and the value as a
	truthy value.
	@class SetUtils
]=]

export type SetUtils<Key> = { [Key]: true }
export type Array<Value> = { [number]: Value }
export type Map<Key, Value> = { [Key]: Value }

local SetUtils = {}

--[=[
	Unions the set with the other set, making a copy.
	@param set table
	@param otherSet table
	@return table
]=]
function SetUtils.union<T, U>(set: SetUtils<T>, otherSet: SetUtils<U>): SetUtils<T | U>
	local newSet: SetUtils<T | U> = {}
	for key, _ in set do
		newSet[key] = true
	end
	for key, _ in otherSet do
		newSet[key] = true
	end
	return newSet
end

--[=[
	Unions the set with the other set, updating the `set`
	@param set table
	@param otherSet table
	@return table
]=]
function SetUtils.unionUpdate<T>(set: SetUtils<T>, otherSet: SetUtils<T>)
	for key, _ in otherSet do
		set[key] = true
	end
end

--[=[
	Finds the set intersection betwen the two sets
	@param set table
	@param otherSet table
	@return table
]=]
function SetUtils.intersection<T>(set: SetUtils<T>, otherSet: SetUtils<T>): SetUtils<T>
	local newSet: SetUtils<T> = {}
	for key, _ in set do
		if otherSet[key] ~= nil then
			newSet[key] = true
		end
	end
	return newSet
end

--[=[
	Makes a copy of the set, making the values as true.
	@param set table
	@return table
]=]
function SetUtils.copy<T>(set: SetUtils<T>): SetUtils<T>
	local newSet: SetUtils<T> = {}
	for key, _ in set do
		newSet[key] = true
	end
	return newSet
end

--[=[
	Counts the number of entries in the set (linear)
]=]
function SetUtils.count<T>(set: SetUtils<T>): number
	local count = 0
	for _, _ in set do
		count += 1
	end
	return count
end

--[=[
	Makes a new set from the given keys of a table
	@param tab table
	@return table
]=]
function SetUtils.fromKeys<T>(tab: Map<T, any>): SetUtils<T>
	local newSet: SetUtils<T> = {}
	for key, _ in tab do
		newSet[key] = true
	end
	return newSet
end

--[=[
	Converts a set from table values.
	@param tab table
	@return table
]=]
function SetUtils.fromTableValue<T>(tab: Map<any, T>): SetUtils<T>
	local set: SetUtils<T> = {}

	for _, value in tab do
		set[value] = true
	end

	return set
end

--[=[
	Converts a set from a list
	@function fromList
	@param tab table
	@return table
	@within SetUtils
]=]
SetUtils.fromList = SetUtils.fromTableValue

--[=[
	Converts a set to a list
	@param set table
	@return table
]=]
function SetUtils.toList<T>(set: { [T]: any }): Array<T>
	local list = {}

	for value, _ in set do
		table.insert(list, value)
	end

	return list
end

--[=[
	Converts a set to a list
	@param set table
	@param otherSet table
	@return table
]=]
function SetUtils.differenceUpdate<T>(set: SetUtils<T>, otherSet: SetUtils<T>)
	for value, _ in otherSet do
		set[value] = nil
	end
end

--[=[
	Computes the set difference between the two sets
	@param set table
	@param otherSet table
	@return table
]=]
function SetUtils.difference<T>(set: SetUtils<T>, otherSet: SetUtils<T>): SetUtils<T>
	local newSet: SetUtils<T> = {}
	for key, _ in set do
		newSet[key] = true
	end
	for key, _ in otherSet do
		newSet[key] = nil
	end
	return newSet
end

return SetUtils
