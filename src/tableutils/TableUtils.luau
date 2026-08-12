--!strict
--[=[
	Provide a variety of utility table operations
	@class TableUtils
]=]

local TableUtils = {}

export type Array<T> = { [number]: T }
export type Map<Key, Value> = { [Key]: Value }

--[=[
	Concats `target` with `source` in-place, modifying the target

	@param target table -- TableUtils to append to
	@param source table -- TableUtils read from
	@return table -- parameter table
]=]
function TableUtils.append<T>(target: Array<T>, source: Array<T>): Array<T>
	for _, value in source do
		target[#target + 1] = value
	end

	return target
end

--[=[
	Shallow merges two tables without modifying either.

	@param orig table -- Original table
	@param new table -- Result
	@return table
]=]
function TableUtils.merge<T, U, T2, U2>(orig: Map<T, U>, new: Map<T2, U2>): Map<T | T2, U | U2>
	local result = table.clone(orig)
	for key, val in new do
		result[key :: any] = val :: any
	end
	return result
end

--[=[
	Reverses the list and returns the reversed copy

	@param orig table -- Original table
	@return table
]=]
function TableUtils.reverse<T>(orig: Array<T>): Array<T>
	local new = {}
	for i = #orig, 1, -1 do
		table.insert(new, orig[i])
	end
	return new
end

--[=[
	Returns a list of all of the values that a table has.

	@param source table -- TableUtils source to extract values from
	@return table -- A list with all the values the table has
]=]
function TableUtils.values<T>(source: Map<any, T>): Array<T>
	local new = {}
	for _, val in source do
		table.insert(new, val)
	end
	return new
end

--[=[
	Returns a list of all of the keys that a table has. (In order of pairs)

	@param source table -- TableUtils source to extract keys from
	@return table -- A list with all the keys the table has
]=]
function TableUtils.keys<T>(source: Map<T, any>): Array<T>
	local new = {}
	for key, _ in source do
		table.insert(new, key)
	end
	return new
end

--[=[
	Shallow merges two lists without modifying either.

	@param orig table -- Original table
	@param new table -- Result
	@return table
]=]
function TableUtils.mergeLists<T, U>(orig: Array<T>, new: Array<U>): Array<T | U>
	local _table: Array<T | U> = {}
	for _, val in orig do
		table.insert(_table, val)
	end
	for _, val in new do
		table.insert(_table, val)
	end
	return _table
end

--[=[
	Maps and flattens a dictionary/map into a single array.

	The transformer receives `(value, key)` and should return
	an array of results which will be appended into the final array.

	Useful for converting keyed tables into flattened lists.

	@param target table -- Source map to transform
	@param transformer function -- Transformer function `(value, key) -> { result }`
	@return table -- Flattened transformed array
]=]
function TableUtils.transformEntries<K, V, U>(target: { [K]: V }, transformer: (V, K) -> { U }): { U }
	local result = {}

	for key, value in target do
		local mapped = transformer(value, key)

		for _, item in mapped do
			table.insert(result, item)
		end
	end

	return result
end

--[=[
	Swaps keys with values, overwriting additional values if duplicated.

	@param orig table -- Original table
	@return table
]=]
function TableUtils.swapKeyValue<Key, Value>(orig: Map<Key, Value>): Map<Value, Key>
	local tab = {}
	for key, val in orig do
		tab[val] = key
	end
	return tab
end

--[=[
	Flips a table so that values become keys and keys become values.
	Alias for swapKeyValue for better discoverability.

	@param orig table -- Original table
	@return table
]=]
function TableUtils.flip<Key, Value>(orig: Map<Key, Value>): Map<Value, Key>
	return TableUtils.swapKeyValue(orig)
end

--[=[
	Converts a table to a list.

	@param _table table -- TableUtils to convert to a list
	@return table
]=]
function TableUtils.toList<T>(_table: Map<any, T>): Array<T>
	local list = {}
	for _, item in _table do
		table.insert(list, item)
	end
	return list
end

--[=[
	Counts the number of items in `_table`.
	Useful since `__len` on table in Lua 5.2 returns just the array length.

	@param _table table -- TableUtils to count
	@return number -- count
]=]
function TableUtils.count(_table: Map<any, any>): number
	local count = 0
	for _, _ in _table do
		count = count + 1
	end
	return count
end

--[=[
	Shallow copies a table from target into a new table

	@function TableUtils.copy
	@param target table -- TableUtils to copy
	@return table -- Result
	@within TableUtils
]=]
TableUtils.copy = table.clone

--[=[
	Deep copies a table including metatables

	@param target table -- TableUtils to deep copy
	@param _deepCopyContext table? -- Context to deepCopy the value in
	@return table -- Result
]=]
function TableUtils.deepCopy<T>(target: T, _deepCopyContext: any?): T
	local context = _deepCopyContext or {}
	if context[target] then
		return context[target]
	end

	if type(target) == "table" then
		local new = {}
		context[target] = new
		for index, value in target do
			new[TableUtils.deepCopy(index, context)] = TableUtils.deepCopy(value, context)
		end
		return setmetatable(new, TableUtils.deepCopy(getmetatable(target), context) :: any) :: any
	else
		return target
	end
end

--[=[
	Overwrites a table's value
	@param target table -- Target table
	@param source table -- TableUtils to read from
	@return table -- target
]=]
function TableUtils.deepOverwrite<K0, K1, V0, V1>(target: Map<K0, V0>, source: Map<K1, V1>): Map<K0 | K1, V0 | V1>
	for index: any, value: any in source do
		if type(target[index]) == "table" and type(value) == "table" then
			target[index] = TableUtils.deepOverwrite(target[index] :: any, value) :: any
		else
			target[index] = value
		end
	end
	return target
end

--[=[
	Mutates target in place until it deep-equals source, keeping the target's
	table identity.

	Unlike [TableUtils.deepOverwrite] this also removes keys that source does not
	have, so the result is source's shape rather than a merge of the two. Reach
	for this when the source is authoritative and a removal has to stick --
	overwriting a `{1, 2, 3}` array with `{1, 2}` leaves the 3 behind.

	```lua
	local target = { Inventory = { 1, 2, 3 } }
	TableUtils.deepOverwrite(target, { Inventory = { 1, 2 } }) --> { Inventory = { 1, 2, 3 } }
	TableUtils.deepSync(target, { Inventory = { 1, 2 } })      --> { Inventory = { 1, 2 } }
	```

	@param target table -- Target table
	@param source table -- Table to read from
	@return table -- target
]=]
function TableUtils.deepSync<K0, K1, V0, V1>(target: Map<K0, V0>, source: Map<K1, V1>): Map<K1, V1>
	for index: any, value: any in source do
		if type(target[index]) == "table" and type(value) == "table" then
			TableUtils.deepSync(target[index] :: any, value)
		else
			target[index] = value
		end
	end

	-- Clearing the current key mid-traversal is well defined in Lua; adding one
	-- would not be, and we never do
	for index: any in target do
		if (source :: any)[index] == nil then
			target[index] = nil
		end
	end

	return (target :: any) :: Map<K1, V1>
end

--[=[
	Gets an index by value, returning `nil` if no index is found.
	@param haystack table -- To search in
	@param needle Value to search for
	@return The index of the value, if found
	@return nil -- if not found
]=]
function TableUtils.getIndex<T>(haystack: Array<T>, needle: T): number?
	assert(needle ~= nil, "Needle cannot be nil")

	for index, item in haystack do
		if needle == item then
			return index
		end
	end

	return nil
end

--[=[
	Recursively prints the table. Does not handle recursive tables.

	@param _table table -- TableUtils to stringify
	@param indent number? -- Indent level
	@param output string? -- Output string, used recursively
	@return string -- The table in string form
]=]
function TableUtils.stringify<Key, Value>(_table: Map<Key, Value>, indent: number?, output: string?): string
	local result = output or tostring(_table)
	local stringIndent = indent or 0
	for key, value in _table do
		local formattedText = "\n" .. string.rep("  ", stringIndent) .. tostring(key) .. ": "
		if type(value) == "table" then
			result = result .. formattedText
			result = TableUtils.stringify(value, stringIndent + 1, result)
		else
			result = result .. formattedText .. tostring(value)
		end
	end
	return result
end

--[=[
	Returns whether `value` is within `table`

	@param _table table -- To search in for value
	@param value any -- Value to search for
	@return boolean -- `true` if within, `false` otherwise
]=]
function TableUtils.contains<T>(_table: { T }, value: T): boolean
	for _, item in _table do
		if item == value then
			return true
		end
	end

	return false
end

--[=[
	Overwrites an existing table with the source values.

	@param target table -- TableUtils to overwite
	@param source table -- Source table to read from
	@return table -- target
]=]
function TableUtils.overwrite(target, source)
	for index, item in source do
		target[index] = item
	end

	return target
end

--[=[
	Deep equivalent comparison of a table assuming keys are indexable in the same way.

	@param target table -- TableUtils to check
	@param source table -- Other table to check
	@return boolean
]=]
function TableUtils.deepEquivalent(target, source): boolean
	if target == source then
		return true
	end

	if type(target) ~= type(source) then
		return false
	end

	if type(target) == "table" then
		for key, value in target do
			if not TableUtils.deepEquivalent(value, source[key]) then
				return false
			end
		end

		for key, value in source do
			if not TableUtils.deepEquivalent(value, target[key]) then
				return false
			end
		end

		return true
	else
		-- target == source should do it.
		return false
	end
end

--[=[
	Takes `count` entries from the table. If the table does not have
	that many entries, will return up to the number the table has to
	provide.

	@param source table -- Source table to retrieve values from
	@param count number -- Number of entries to take
	@return table -- List with the entries retrieved
]=]
function TableUtils.take<T>(source: Array<T>, count: number): Array<T>
	local n = math.min(#source, count)
	local newTable = table.create(n)

	for i = 1, n do
		newTable[i] = source[i]
	end

	return newTable
end

local function errorOnIndex(_, index)
	error(string.format("Bad index %q", tostring(index)), 2)
end

local READ_ONLY_METATABLE = {
	__index = errorOnIndex,
	__newindex = errorOnIndex,
}

--[=[
	Sets a metatable on a table such that it errors when
	indexing a nil value

	@param target table -- TableUtils to error on indexing
	@return table -- The same table, with the metatable set to readonly
]=]
function TableUtils.readonly<T>(target: T): T
	return table.freeze(setmetatable(target :: any, READ_ONLY_METATABLE)) :: any
end

--[=[
	Sets a metatable on a table such that it errors when
	indexing a nil value

	@param target table -- TableUtils to error on indexing
	@return table -- The same table, with the target set to error on nil
]=]
function TableUtils.errorOnNilIndex<T>(target: T): T
	return setmetatable(target :: any, READ_ONLY_METATABLE)
end

--[=[
	Recursively sets the table as ReadOnly

	@param target table -- TableUtils to error on indexing
	@return table -- The same table
]=]
function TableUtils.deepReadonly<T>(target: T): T
	for _, item in target :: any do
		if type(item) == "table" then
			TableUtils.deepReadonly(item)
		end
	end

	return TableUtils.readonly(target)
end

--[=[
	Reduces a table into a single value.

	@param target table -- TableUtils to reduce
	@param reducer function -- Reducer function
	@param initial any -- Initial value
	@return any -- Result
]=]
function TableUtils.reduce<T, U>(target: T, reducer: (U, T) -> U, initial: U): U
	local result = initial
	for _, item in target :: any do
		result = reducer(result, item)
	end
	return result
end

--[=[
	Maps a table's values to a new table using a mapper function.

	@param target table -- TableUtils to map
	@param mapper function -- Mapper function (value, key) -> newValue
	@return table -- New table with mapped values
]=]
function TableUtils.map<T, U>(target: Array<T>, mapper: (T, number) -> U): Array<U>
	local result = {}
	for index, value in target do
		result[index] = mapper(value, index)
	end
	return result
end

--[=[
	Filters a table's values using a predicate function.

	@param target table -- TableUtils to filter
	@param predicate function -- Predicate function (value, key) -> boolean
	@return table -- New table with filtered values
]=]
function TableUtils.filter<T>(target: Array<T>, predicate: (T, number) -> boolean): Array<T>
	local result = {}
	for index, value in target do
		if predicate(value, index) then
			table.insert(result, value)
		end
	end
	return result
end

--[=[
	Finds the first value in a table that matches the predicate.

	@param target table -- TableUtils to search
	@param predicate function -- Predicate function (value, key) -> boolean
	@return any? -- The first matching value, or nil if not found
	@return number? -- The index of the first matching value, or nil if not found
]=]
function TableUtils.find<T>(target: Array<T>, predicate: (T, number) -> boolean): (T?, number?)
	for index, value in target do
		if predicate(value, index) then
			return value, index
		end
	end
	return nil, nil
end

--[=[
	Checks if every value in a table matches the predicate.

	@param target table -- TableUtils to check
	@param predicate function -- Predicate function (value, key) -> boolean
	@return boolean -- True if all values match, false otherwise
]=]
function TableUtils.every<T>(target: Array<T>, predicate: (T, number) -> boolean): boolean
	for index, value in target do
		if not predicate(value, index) then
			return false
		end
	end
	return true
end

--[=[
	Checks if any value in a table matches the predicate.

	@param target table -- TableUtils to check
	@param predicate function -- Predicate function (value, key) -> boolean
	@return boolean -- True if any value matches, false otherwise
]=]
function TableUtils.some<T>(target: Array<T>, predicate: (T, number) -> boolean): boolean
	for index, value in target do
		if predicate(value, index) then
			return true
		end
	end
	return false
end

--[=[
	Flattens a nested array by one level.

	@param target table -- TableUtils to flatten
	@return table -- Flattened table
]=]
function TableUtils.flat<T>(target: Array<Array<T>>): Array<T>
	local result = {}
	for _, subTable in target do
		if type(subTable) == "table" then
			for _, value in subTable do
				table.insert(result, value)
			end
		else
			table.insert(result, subTable :: any)
		end
	end
	return result
end

--[=[
	Maps and flattens a table in one operation.

	@param target table -- TableUtils to map and flatten
	@param mapper function -- Mapper function (value, key) -> table
	@return table -- Mapped and flattened table
]=]
function TableUtils.flatMap<T, U>(target: Array<T>, mapper: (T, number) -> Array<U>): Array<U>
	local result = {}
	for index, value in target do
		local mapped = mapper(value, index)
		for _, item in mapped do
			table.insert(result, item)
		end
	end
	return result
end

--[=[
	Shuffles a table randomly (Fisher-Yates shuffle).

	@param target table -- TableUtils to shuffle
	@return table -- New shuffled table
]=]
function TableUtils.shuffle<T>(target: Array<T>): Array<T>
	local result = table.clone(target)
	for i = #result, 2, -1 do
		local j = math.random(1, i)
		result[i], result[j] = result[j], result[i]
	end
	return result
end

--[=[
	Randomly samples n items from a table without replacement.

	@param target table -- TableUtils to sample from
	@param count number -- Number of items to sample
	@return table -- New table with sampled items
]=]
function TableUtils.sample<T>(target: Array<T>, count: number): Array<T>
	local shuffled = TableUtils.shuffle(target)
	return TableUtils.take(shuffled, count)
end

--[=[
	Checks if a table is empty.

	@param target table -- TableUtils to check
	@return boolean -- True if empty, false otherwise
]=]
function TableUtils.isEmpty(target: Map<any, any>): boolean
	return next(target) == nil
end

--[=[
	Removes an element at the specified index by swapping it with the last element.
	This is faster than table.remove but does not preserve order.

	@param target table -- TableUtils to modify
	@param index number -- Index to remove
	@return any? -- The removed value
]=]
function TableUtils.swapRemove<T>(target: Array<T>, index: number): T?
	local length = #target
	if index < 1 or index > length then
		return nil
	end

	local value = target[index]
	target[index] = target[length]
	target[length] = nil
	return value
end

--[=[
	Removes the first occurrence of a value by swapping it with the last element.
	This is faster than table.remove but does not preserve order.

	@param target table -- TableUtils to modify
	@param value any -- Value to remove
	@return boolean -- True if value was found and removed, false otherwise
]=]
function TableUtils.swapRemoveFirstValue<T>(target: Array<T>, value: T): boolean
	local index = TableUtils.getIndex(target, value)
	if index then
		TableUtils.swapRemove(target, index)
		return true
	end
	return false
end

--[=[
	Assigns properties from source tables to target table (shallow copy).
	Similar to Object.assign in JavaScript.

	@param target table -- Target table to assign to
	@param ... table -- Source tables to assign from
	@return table -- The target table
]=]
function TableUtils.assign<K, V>(target: Map<K, V>, ...: Map<K, V>): Map<K, V>
	for _, source in { ... } do
		for key, value in source do
			target[key] = value
		end
	end
	return target
end

--[=[
	Extends an array with values from other arrays.

	@param target table -- Target array to extend
	@param ... table -- Source arrays to extend from
	@return table -- The target array
]=]
function TableUtils.extend<T>(target: Array<T>, ...: Array<T>): Array<T>
	for _, source in { ... } do
		for _, value in source do
			table.insert(target, value)
		end
	end
	return target
end

--[=[
	Zips multiple arrays together into an array of tuples.

	@param ... table -- Arrays to zip
	@return table -- Array of tuples
]=]
function TableUtils.zip<T>(...: Array<T>): Array<Array<T>>
	local arrays = { ... }
	local result = {}
	local minLength = math.huge

	for _, array in arrays do
		minLength = math.min(minLength, #array)
	end

	for i = 1, minLength do
		local tuple = {}
		for _, array in arrays do
			table.insert(tuple, array[i])
		end
		table.insert(result, tuple)
	end

	return result
end

--[=[
	Truncates a table to a specified length.

	@param target table -- TableUtils to truncate
	@param length number -- New length
	@return table -- The same table, truncated
]=]
function TableUtils.truncate<T>(target: Array<T>, length: number): Array<T>
	for i = #target, length + 1, -1 do
		target[i] = nil
	end
	return target
end

--[=[
	Reconciles two tables, adding/updating keys from source and removing keys not in source.
	Useful for syncing state.

	@param target table -- Target table to reconcile
	@param source table -- Source table to reconcile from
	@return table -- The target table
]=]
function TableUtils.reconcile<K, V>(target: Map<K, V>, source: Map<K, V>): Map<K, V>
	-- Remove keys not in source
	for key in target do
		if source[key] == nil then
			target[key] = nil
		end
	end

	-- Add/update keys from source
	for key, value in source do
		target[key] = value
	end

	return target
end

--[=[
	Syncs target table with source table, preserving existing tables when possible.
	Useful for deep reconciliation.

	@param target table -- Target table to sync
	@param source table -- Source table to sync from
	@return table -- The target table
]=]
function TableUtils.sync<K, V>(target: Map<K, V>, source: Map<K, V>): Map<K, V>
	-- Remove keys not in source
	for key in target do
		if source[key] == nil then
			target[key] = nil
		end
	end

	-- Add/update keys from source
	for key, value in source do
		if type(value) == "table" and type(target[key]) == "table" then
			TableUtils.sync(target[key] :: any, value :: any)
		else
			target[key] = value
		end
	end

	return target
end

--[=[
	Executes a function for each element in the table.

	@param target table -- TableUtils to iterate over
	@param callback function -- Function to execute for each element (value, index) -> void
]=]
function TableUtils.forEach<T>(target: Array<T>, callback: (T, number) -> ()): ()
	for index, value in target do
		callback(value, index)
	end
end

--[=[
	Compares two tables and returns only the changed values.
	Returns a table containing keys where oldTable[key] ~= newTable[key].

	@param oldTable table -- The original table
	@param newTable table -- The new table to compare against
	@return table -- A table containing only the changed keys and their new values
]=]
function TableUtils.diff<K, V>(oldTable: Map<K, V>, newTable: Map<K, V>): Map<K, V>
	local changes = {}

	for key, newValue in newTable do
		if oldTable[key] ~= newValue then
			changes[key] = newValue
		end
	end

	return changes
end

--[=[
	Deep compares two tables and returns only the changed values (including nested changes).
	For nested tables, returns only the changed nested keys.

	@param oldTable table -- The original table
	@param newTable table -- The new table to compare against
	@return table -- A table containing only the changed keys and their new values (nested)
]=]
function TableUtils.deepDiff<K, V>(oldTable: Map<K, V>, newTable: Map<K, V>): Map<K, V>
	local changes = {}

	for key, newValue in newTable do
		local oldValue = oldTable[key]

		if type(newValue) == "table" and type(oldValue) == "table" then
			-- Both are tables, do deep comparison
			local nestedChanges = TableUtils.deepDiff(oldValue :: any, newValue :: any)
			if next(nestedChanges) then
				-- Only include if there are actual nested changes
				changes[key] = nestedChanges :: any
			end
		elseif oldValue ~= newValue then
			-- Values are different (or one is table and other isn't)
			changes[key] = newValue
		end
	end

	return changes
end

--[=[
	Filters a map's key-value pairs using a predicate function.

	@param target table -- TableUtils to filter
	@param predicate function -- Predicate function (value, key) -> boolean
	@return table -- New table with filtered key-value pairs
]=]
function TableUtils.filterMap<K, V>(target: { [K]: V }, predicate: (V, K) -> boolean): { [K]: V }
	local result = {}

	for key, value in target do
		if predicate(value, key) then
			result[key] = value
		end
	end

	return result
end

TableUtils.sort = table.sort
TableUtils.insert = table.insert
TableUtils.remove = table.remove
TableUtils.concat = table.concat
TableUtils.unpack = table.unpack
TableUtils.pack = table.pack
TableUtils.move = table.move
TableUtils.create = table.create
TableUtils.clear = table.clear
TableUtils.freeze = table.freeze
TableUtils.isfrozen = table.isfrozen
-- TableUtils.clone is already defined above as TableUtils.copy = table.clone
-- TableUtils.find is already defined above with custom implementation

TableUtils.maxn = table.maxn

return TableUtils
