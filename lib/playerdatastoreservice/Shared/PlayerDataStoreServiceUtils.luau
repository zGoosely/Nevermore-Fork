--!strict
--[=[
    @utils PlayerDataStoreServiceUtils
]=]

const require = require("../../Loader").load()

const DefaultValueUtils = require("DefaultValueUtils")
const ObservableMap = require("ObservableMap")
const PlayerDataStoreServiceProfile = require("PlayerDataStoreServiceProfile")
const StringUtils = require("StringUtils")
const TableUtils = require("TableUtils")

const SETTINGS_KEY = "Settings"

const PlayerDataStoreServiceUtils = {}

local function getSettingsTemplate(): { [string]: any }
	const settings = rawget(PlayerDataStoreServiceProfile.Get().Template :: any, SETTINGS_KEY)
	return if type(settings) == "table" then settings else {}
end

--[=[
    Splits a dot-separated path into its root key and the remaining path, if
    any. The root key is what an ObservableMap of profile data is keyed on; the
    remainder is resolved against that key's value.

    @within PlayerDataStoreServiceUtils
    @param path string
    @return (string, string?)
]=]
function PlayerDataStoreServiceUtils.splitValuePath(path: string): (string, string?)
	const parts = StringUtils.split(path, ".")

	if #parts == 1 then
		return parts[1], nil
	end

	return parts[1], table.concat(parts, ".", 2)
end

--[=[
	Returns whether two data paths overlap as an ancestor, descendant, or exact
	match. Segment boundaries are respected, so `Inventory.Item` does not overlap
	`Inventory.Items`.

	@within PlayerDataStoreServiceUtils
	@param left string
	@param right string
	@return boolean
]=]
function PlayerDataStoreServiceUtils.valuePathsOverlap(left: string, right: string): boolean
	assert(type(left) == "string" and left ~= "", "Bad left")
	assert(type(right) == "string" and right ~= "", "Bad right")

	return left == right
		or string.sub(left, 1, #right + 1) == right .. "."
		or string.sub(right, 1, #left + 1) == left .. "."
end

--[=[
    Reads a value out of an ObservableMap of profile data using a dot-separated
    path, descending into the root key's value for nested paths.

    @within PlayerDataStoreServiceUtils
    @param map ObservableMap<string, any>
    @param path string
    @return any
]=]
function PlayerDataStoreServiceUtils.readObservableValuePath(
	map: ObservableMap.ObservableMap<string, any>,
	path: string
): any
	const rootKey, nestedPath = PlayerDataStoreServiceUtils.splitValuePath(path)
	const rootValue = map:Get(rootKey)

	if not nestedPath then
		return rootValue
	end

	return PlayerDataStoreServiceUtils.readValuePath(rootValue, nestedPath)
end

--[=[
    Writes a value into an ObservableMap of profile data using a dot-separated
    path. Nested writes copy the root value before mutating it, since the map
    ignores a Set that carries the same reference it already holds.

    @within PlayerDataStoreServiceUtils
    @param map ObservableMap<string, any>
    @param path string
    @param value any
]=]
function PlayerDataStoreServiceUtils.writeObservableValuePath(
	map: ObservableMap.ObservableMap<string, any>,
	path: string,
	value: any
)
	const rootKey, nestedPath = PlayerDataStoreServiceUtils.splitValuePath(path)

	if not nestedPath then
		map:Set(rootKey, value)
		return
	end

	const currentRoot = map:Get(rootKey)
	const newRoot = if type(currentRoot) == "table" then TableUtils.deepCopy(currentRoot) else {}

	PlayerDataStoreServiceUtils.writeValuePath(newRoot, nestedPath, value)
	map:Set(rootKey, newRoot)
end

--[=[
    Reads a value from a table using a dot-separated path.

    @within PlayerDataStoreServiceUtils
    @param target table
    @param path string
    @return any
]=]
function PlayerDataStoreServiceUtils.readValuePath(target: any, path: string): any
	local current = target

	for _, key in StringUtils.split(path, ".") do
		if type(current) ~= "table" then
			return nil
		end

		current = current[key]

		if current == nil then
			return nil
		end
	end

	return current
end

--[=[
    Writes a value to a table using a dot-separated path.
    Missing intermediate tables are created automatically.

    @within PlayerDataStoreServiceUtils
    @param target table
    @param path string
    @param value any
    @return any
]=]
function PlayerDataStoreServiceUtils.writeValuePath(target: any, path: string, value: any): any
	local current = target
	const parts = StringUtils.split(path, ".")

	for i = 1, #parts - 1 do
		local key = parts[i]

		assert(type(current) == "table", ("Invalid path '%s'"):format(path))

		if current[key] == nil then
			current[key] = {}
		end

		assert(
			type(current[key]) == "table",
			("Invalid path '%s': '%s' is %s, expected table"):format(
				path,
				table.concat(parts, ".", 1, i),
				type(current[key])
			)
		)

		current = current[key]
	end

	current[parts[#parts]] = value
	return value
end

--[=[
    Returns the profile root key settings are stored under.

    @within PlayerDataStoreServiceUtils
    @return string
]=]
function PlayerDataStoreServiceUtils.getSettingsKey(): string
	return SETTINGS_KEY
end

--[=[
    Returns the profile path a setting is stored at.

    @within PlayerDataStoreServiceUtils
    @param name string
    @return string
]=]
function PlayerDataStoreServiceUtils.getSettingPath(name: string): string
	return `{SETTINGS_KEY}.{name}`
end

--[=[
    Returns every setting name the profile template declares.

    @within PlayerDataStoreServiceUtils
    @return { string }
]=]
function PlayerDataStoreServiceUtils.getSettingNames(): { string }
	const names = {}

	for name in getSettingsTemplate() do
		table.insert(names, name)
	end

	return names
end

--[=[
    Returns whether a name is a setting, meaning a key of the profile template's
    Settings table. Gates reads -- see [PlayerDataStoreServiceUtils.isWritableSettingName]
    for whether a client may also write it.

    @within PlayerDataStoreServiceUtils
    @param name string
    @return boolean
]=]
function PlayerDataStoreServiceUtils.isSettingName(name: string): boolean
	if type(name) ~= "string" then
		return false
	end

	return getSettingsTemplate()[name] ~= nil
end

--[=[
    Returns whether a client may write a setting: a key of the template whose
    default is a primitive.

    Table-valued settings are excluded deliberately. Validity is inferred from the
    default's type, and a type check cannot say anything about a table's shape --
    a wrong-shaped table written into a profile makes the next `Schema.ser` throw,
    which kills that player's whole profile buffer on every future join. Table
    settings stay server-only, through [PlayerDataStoreService.SetValue].

    @within PlayerDataStoreServiceUtils
    @param name string
    @return boolean
]=]
function PlayerDataStoreServiceUtils.isWritableSettingName(name: string): boolean
	if not PlayerDataStoreServiceUtils.isSettingName(name) then
		return false
	end

	-- type rather than typeof throughout: writable settings are primitives, which
	-- the two agree on, and a Roblox datatype reads as "userdata" here, so it
	-- fails the whitelist rather than being mistaken for a primitive
	const defaultType = type(getSettingsTemplate()[name])

	return defaultType == "boolean" or defaultType == "string" or defaultType == "number"
end

--[=[
    Returns whether a value may be written to a setting: the same type as the
    template's default for it, and a real number if numeric.

    @within PlayerDataStoreServiceUtils
    @param name string
    @param value any
    @return boolean
]=]
function PlayerDataStoreServiceUtils.isValidSettingValue(name: string, value: any): boolean
	if not PlayerDataStoreServiceUtils.isWritableSettingName(name) then
		return false
	end

	const valueType = type(value)
	if valueType ~= type(getSettingsTemplate()[name]) then
		return false
	end

	if valueType == "number" then
		-- NaN and the infinities are all numbers to a type check, and all three
		-- would break the profile's serializer
		return value == value and value ~= math.huge and value ~= -math.huge
	end

	return true
end

--[=[
    Returns a copy of profile data safe to send to the client, with every hidden
    key blanked to its default value.

    The values are blanked rather than removed because the payload is serialized
    against a fixed schema, which has no way to express an absent key. The client
    is sent the hidden key list alongside and drops them on arrival.

    @within PlayerDataStoreServiceUtils
    @param data table
    @param hiddenKeys { string }
    @return table
]=]
function PlayerDataStoreServiceUtils.getReplicatedData(data: any, hiddenKeys: { string }): any
	if #hiddenKeys == 0 then
		return data
	end

	const replicated = TableUtils.deepCopy(data)
	for _, keyName in hiddenKeys do
		const currentValue = PlayerDataStoreServiceUtils.readValuePath(replicated, keyName)
		if currentValue == nil then
			continue
		end

		const success, defaultValue = pcall(DefaultValueUtils.toDefaultValue, currentValue)
		if not success then
			warn(
				`[PlayerDataStoreServiceUtils] - Cannot blank hidden key {keyName} ({defaultValue}), it will replicate as-is`
			)
			continue
		end

		PlayerDataStoreServiceUtils.writeValuePath(replicated, keyName, defaultValue)
	end

	return replicated
end

--[=[
    Returns the root keys whose value differs between two profile data tables,
    removals included.

    Replication is done a whole root key at a time because a dot-separated path
    cannot express a removal either: the client would never hear that an entry
    left an array. Sending the root wholesale costs bandwidth but cannot desync.

    @within PlayerDataStoreServiceUtils
    @param oldData table
    @param newData table
    @return { string }
]=]
function PlayerDataStoreServiceUtils.getChangedRootKeys(oldData: any, newData: any): { string }
	const changed = {}

	for key, newValue in newData do
		if not TableUtils.deepEquivalent(oldData[key], newValue) then
			table.insert(changed, key)
		end
	end

	for key in oldData do
		if newData[key] == nil then
			table.insert(changed, key)
		end
	end

	return changed
end

--[=[
	Returns changed values as dot-separated paths.

	@param oldData table
	@param newData table
	@param prefix string?
	@return table
]=]
function PlayerDataStoreServiceUtils.deepDiffPaths(oldData: any, newData: any, prefix: string?): { [string]: any }
	const changes = {}

	for key, newValue in newData do
		const path = if prefix then prefix .. "." .. key else key
		const oldValue = oldData[key]

		if type(newValue) == "table" and type(oldValue) == "table" then
			const nestedChanges = PlayerDataStoreServiceUtils.deepDiffPaths(oldValue, newValue, path)

			for nestedKey, nestedValue in nestedChanges do
				changes[nestedKey] = nestedValue
			end
		elseif oldValue ~= newValue then
			changes[path] = newValue
		end
	end

	return changes
end

return PlayerDataStoreServiceUtils
