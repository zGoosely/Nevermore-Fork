--!strict
--[=[
	Wraps one key in a Roblox DataStore with cached reads, staged writes, atomic
	saves, and optional autosaving.

	This is the server-state datastore used by [GameDataStoreService] and
	[PrivateServerDataStoreService]. Player profiles remain owned by
	[PlayerDataStoreService].

	@class DataStore
	@server
]=]

const require = require("../Loader").load()

const DataStorePromises = require("DataStorePromises")
const Maid = require("Maid")
const Promise = require("Promise")
const TableUtils = require("TableUtils")
const t = require("t")

const DEFAULT_AUTO_SAVE_TIME_SECONDS = 5 * 60
const DELETE_TOKEN = table.freeze({})
const isData = t.map(t.union(t.string, t.number), t.any)
const isDataStoreKey = t.union(t.string, t.number)

const DataStore = {}
DataStore.ClassName = "DataStore"
DataStore.__index = DataStore

type DataStoreKey = string | number
type Data = { [DataStoreKey]: any }

export type DataStore = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_robloxDataStore: DataStorePromises.RobloxDataStore,
		_key: string,
		_loadedData: Data?,
		_loadPromise: Promise.Promise<any>?,
		_savePromise: Promise.Promise<any>?,
		_syncPromise: Promise.Promise<any>?,
		_pendingWrites: Data,
		_writeVersions: { [DataStoreKey]: number },
		_nextWriteVersion: number,
		_autoSaveTimeSeconds: number?,
		_autoSaveThread: thread?,
		_syncOnSave: boolean,
		_didLoadFail: boolean,
		_isDestroyed: boolean,
	},
	{} :: typeof({ __index = DataStore })
))

function DataStore.new(robloxDataStore: DataStorePromises.RobloxDataStore, key: string): DataStore
	assert(DataStorePromises.isDataStore(robloxDataStore), "Bad robloxDataStore")
	assert(t.string(key) and key ~= "", "Bad key")

	const self = setmetatable({}, DataStore) :: DataStore
	self._maid = Maid.new()
	self._robloxDataStore = robloxDataStore
	self._key = key
	self._loadedData = nil
	self._loadPromise = nil
	self._savePromise = nil
	self._syncPromise = nil
	self._pendingWrites = {}
	self._writeVersions = {}
	self._nextWriteVersion = 0
	self._autoSaveTimeSeconds = DEFAULT_AUTO_SAVE_TIME_SECONDS
	self._autoSaveThread = nil
	self._syncOnSave = false
	self._didLoadFail = false
	self._isDestroyed = false

	self:_scheduleAutoSave()

	return self
end

--[=[
	Stages a value to be written by the next save. Passing nil removes the key.

	@within DataStore
	@param key string | number
	@param value any
]=]
function DataStore.Store(self: DataStore, key: DataStoreKey, value: any): ()
	assert(isDataStoreKey(key), "Bad key")
	assert(not self._isDestroyed, "DataStore is destroyed")

	self._nextWriteVersion += 1
	self._writeVersions[key] = self._nextWriteVersion
	self._pendingWrites[key] = if value == nil then DELETE_TOKEN else TableUtils.deepCopy(value)

	if self._loadedData then
		if value == nil then
			self._loadedData[key] = nil
		else
			self._loadedData[key] = TableUtils.deepCopy(value)
		end
	end
end

--[=[
	Loads one value, returning the supplied default when the key is absent.

	@within DataStore
	@param key string | number
	@param defaultValue any
	@return Promise<any>
]=]
function DataStore.Load(self: DataStore, key: DataStoreKey?, defaultValue: any): Promise.Promise<any>
	assert(t.optional(isDataStoreKey)(key), "Bad key")
	assert(not self._isDestroyed, "DataStore is destroyed")

	if key == nil then
		return self:LoadAll(defaultValue)
	end

	return self:_promiseLoad():Then(function(data: Data)
		const value = data[key]
		if value == nil then
			return TableUtils.deepCopy(defaultValue)
		end

		return TableUtils.deepCopy(value)
	end)
end

--[=[
	Loads the full value stored for this server-state key.

	@within DataStore
	@param defaultValue any
	@return Promise<any>
]=]
function DataStore.LoadAll(self: DataStore, defaultValue: any): Promise.Promise<any>
	assert(not self._isDestroyed, "DataStore is destroyed")

	return self:_promiseLoad():Then(function(data: Data)
		if next(data) == nil and defaultValue ~= nil then
			return TableUtils.deepCopy(defaultValue)
		end

		return TableUtils.deepCopy(data)
	end)
end

--[=[
	Saves every staged write atomically.

	@within DataStore
	@return Promise<()>
]=]
function DataStore.Save(self: DataStore): Promise.Promise<any>
	assert(not self._isDestroyed, "DataStore is destroyed")

	if self._savePromise then
		return self._savePromise:Then(function()
			return self:Save()
		end)
	end
	if self._syncPromise then
		return self._syncPromise:Then(function()
			return self:Save()
		end)
	end

	if next(self._pendingWrites) == nil then
		if self._syncOnSave then
			return self:Sync()
		end

		return Promise.resolved()
	end

	const pendingWrites = {}
	for writeKey, value in self._pendingWrites do
		pendingWrites[writeKey] = if value == DELETE_TOKEN then DELETE_TOKEN else TableUtils.deepCopy(value)
	end
	const writeVersions = table.clone(self._writeVersions)

	self._savePromise = self._maid
		:GivePromise(DataStorePromises.updateAsync(self._robloxDataStore, self._key, function(storedData: any)
			assert(t.optional(isData)(storedData), "Stored server data must be a table")

			const nextData = if storedData == nil then {} else TableUtils.deepCopy(storedData)
			for writeKey, value in pendingWrites do
				if value == DELETE_TOKEN then
					nextData[writeKey] = nil
				else
					nextData[writeKey] = TableUtils.deepCopy(value)
				end
			end

			return nextData
		end))
		:Then(function(savedData: any)
			assert(isData(savedData), "Saved server data must be a table")

			for writeKey, version in writeVersions do
				if self._writeVersions[writeKey] == version then
					self._writeVersions[writeKey] = nil
					self._pendingWrites[writeKey] = nil
				end
			end

			self._loadedData = self:_applyPendingWrites(savedData)
		end)
		:Finally(function()
			self._savePromise = nil
		end)

	return self._savePromise
end

--[=[
	Refreshes this store from Roblox while retaining unsaved local writes.

	@within DataStore
	@return Promise<()>
]=]
function DataStore.Sync(self: DataStore): Promise.Promise<any>
	assert(not self._isDestroyed, "DataStore is destroyed")

	if self._savePromise then
		return self._savePromise:Then(function()
			return self:Sync()
		end)
	end
	if self._syncPromise then
		return self._syncPromise
	end

	self._syncPromise = self:_promiseLoadFresh()
		:Then(function()
			return nil
		end)
		:Finally(function()
			self._syncPromise = nil
		end)

	return self._syncPromise
end

--[=[
	Sets how frequently staged writes are saved. Pass nil to disable autosaving.

	@within DataStore
	@param autoSaveTimeSeconds number?
]=]
function DataStore.SetAutoSaveTimeSeconds(self: DataStore, autoSaveTimeSeconds: number?): ()
	assert(t.optional(t.numberPositive)(autoSaveTimeSeconds), "Bad autoSaveTimeSeconds")

	self._autoSaveTimeSeconds = autoSaveTimeSeconds
	self:_scheduleAutoSave()
end

--[=[
	Returns the current autosave interval.

	@within DataStore
	@return number?
]=]
function DataStore.GetAutoSaveTimeSeconds(self: DataStore): number?
	return self._autoSaveTimeSeconds
end

--[=[
	Sets whether a save with no pending writes should still refresh remote data.

	@within DataStore
	@param syncOnSave boolean
]=]
function DataStore.SetSyncOnSave(self: DataStore, syncOnSave: boolean): ()
	assert(t.boolean(syncOnSave), "Bad syncOnSave")
	self._syncOnSave = syncOnSave
end

--[=[
	Returns whether this datastore has encountered a load failure.

	@within DataStore
	@return boolean
]=]
function DataStore.DidLoadFail(self: DataStore): boolean
	return self._didLoadFail
end

--[=[
	Returns the underlying Roblox DataStore key.

	@within DataStore
	@return string
]=]
function DataStore.GetKey(self: DataStore): string
	return self._key
end

function DataStore._promiseLoad(self: DataStore): Promise.Promise<any>
	if self._loadedData then
		return Promise.resolved(self._loadedData)
	end
	if self._loadPromise then
		return self._loadPromise
	end

	self._loadPromise = self:_promiseLoadFresh():Finally(function()
		self._loadPromise = nil
	end)

	return self._loadPromise
end

function DataStore._promiseLoadFresh(self: DataStore): Promise.Promise<any>
	return self._maid
		:GivePromise(DataStorePromises.getAsync(self._robloxDataStore, self._key))
		:Then(function(storedData: any)
			assert(t.optional(isData)(storedData), "Stored server data must be a table")

			self._didLoadFail = false
			self._loadedData = self:_applyPendingWrites(storedData or {})

			return self._loadedData
		end)
		:Catch(function(...: any)
			self._didLoadFail = true
			return Promise.rejected(...)
		end)
end

function DataStore._applyPendingWrites(self: DataStore, storedData: Data): Data
	const mergedData = TableUtils.deepCopy(storedData)

	for writeKey, value in self._pendingWrites do
		if value == DELETE_TOKEN then
			mergedData[writeKey] = nil
		else
			mergedData[writeKey] = TableUtils.deepCopy(value)
		end
	end

	return mergedData
end

function DataStore._scheduleAutoSave(self: DataStore): ()
	if self._autoSaveThread then
		task.cancel(self._autoSaveThread)
		self._autoSaveThread = nil
	end

	const autoSaveTimeSeconds = self._autoSaveTimeSeconds
	if self._isDestroyed or autoSaveTimeSeconds == nil then
		return
	end

	self._autoSaveThread = task.delay(autoSaveTimeSeconds, function()
		self._autoSaveThread = nil
		if self._isDestroyed then
			return
		end

		self:Save()
			:Catch(function(errorMessage: any)
				warn(`[DataStore] - Failed to autosave {self._key}: {errorMessage}`)
			end)
			:Finally(function()
				self:_scheduleAutoSave()
			end)
	end)
end

function DataStore.Destroy(self: DataStore): ()
	if self._isDestroyed then
		return
	end

	self._isDestroyed = true
	if self._autoSaveThread then
		task.cancel(self._autoSaveThread)
		self._autoSaveThread = nil
	end

	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return DataStore
