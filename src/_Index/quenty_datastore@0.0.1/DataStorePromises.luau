--!strict
--[=[
	Promise wrappers for Roblox DataStore operations.

	@util DataStorePromises
	@server
]=]

const DataStoreService = game:GetService("DataStoreService")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const t = require("@game/ReplicatedStorage/Packages/t")

const isRobloxDataStore = t.union(
	t.Instance,
	t.interface({
		GetAsync = t.callback,
		UpdateAsync = t.callback,
	})
)

const DataStorePromises = {}

export type RobloxDataStore = DataStore

--[=[
	Returns whether a value supports the Roblox DataStore operations used by
	this package. Duck-typed stores are accepted for local testing.

	@within DataStorePromises
	@param robloxDataStore any
	@return boolean
]=]
function DataStorePromises.isDataStore(robloxDataStore: any): boolean
	return isRobloxDataStore(robloxDataStore)
end

--[=[
	Resolves a standard Roblox DataStore.

	@within DataStorePromises
	@param name string
	@param scope string
	@return Promise<DataStore>
]=]
function DataStorePromises.promiseDataStore(name: string, scope: string): Promise.Promise<DataStore>
	assert(t.string(name) and name ~= "", "Bad name")
	assert(t.string(scope) and scope ~= "", "Bad scope")

	return Promise.spawn(function(resolve, reject)
		const success, dataStoreOrError = pcall(DataStoreService.GetDataStore, DataStoreService, name, scope)
		if not success then
			reject(dataStoreOrError)
			return
		end

		resolve(dataStoreOrError)
	end)
end

--[=[
	Reads a key without Roblox's local read cache.

	@within DataStorePromises
	@param robloxDataStore DataStore
	@param key string
	@return Promise<any>
]=]
function DataStorePromises.getAsync(robloxDataStore: DataStore, key: string): Promise.Promise<any>
	assert(DataStorePromises.isDataStore(robloxDataStore), "Bad robloxDataStore")
	assert(t.string(key) and key ~= "", "Bad key")

	return Promise.spawn(function(resolve, reject)
		const options = Instance.new("DataStoreGetOptions")
		options.UseCache = false

		const success, valueOrError = pcall(function()
			return robloxDataStore:GetAsync(key, options)
		end)
		if not success then
			reject(valueOrError)
			return
		end

		resolve(valueOrError)
	end)
end

--[=[
	Updates a key atomically.

	@within DataStorePromises
	@param robloxDataStore DataStore
	@param key string
	@param updateCallback (any) -> any
	@return Promise<any>
]=]
function DataStorePromises.updateAsync(
	robloxDataStore: DataStore,
	key: string,
	updateCallback: (any) -> any
): Promise.Promise<any>
	assert(DataStorePromises.isDataStore(robloxDataStore), "Bad robloxDataStore")
	assert(t.string(key) and key ~= "", "Bad key")
	assert(t.callback(updateCallback), "Bad updateCallback")

	return Promise.spawn(function(resolve, reject)
		const success, valueOrError = pcall(function()
			return robloxDataStore:UpdateAsync(key, updateCallback)
		end)
		if not success then
			reject(valueOrError)
			return
		end

		resolve(valueOrError)
	end)
end

return DataStorePromises
