--!strict
--[=[
	Provides server state keyed to the current private or reserved server.
	Public servers share the fallback key "main".

	@class PrivateServerDataStoreService
	@server
]=]
const BindToCloseService = require("@game/ReplicatedStorage/Packages/BindToCloseService")
const DataStore = require("./DataStore")
const DataStorePromises = require("./DataStorePromises")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

const DATASTORE_NAME = "PrivateServerDataStores"
const DATASTORE_SCOPE = "Version1"
const MAIN_SERVER_KEY = "main"

const PrivateServerDataStoreService = {}
PrivateServerDataStoreService.ServiceName = "PrivateServerDataStoreService"
PrivateServerDataStoreService.ServerOnly = true

export type PrivateServerDataStoreService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_bindToCloseService: BindToCloseService.BindToCloseService,
		_dataStorePromise: Promise.Promise<DataStore.DataStore>?,
		_dataStorePromises: { [string]: Promise.Promise<DataStore.DataStore> },
		_robloxDataStorePromise: Promise.Promise<any>?,
		_customKey: string?,
	},
	{} :: typeof({ __index = PrivateServerDataStoreService })
))

function PrivateServerDataStoreService.Init(self: PrivateServerDataStoreService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._bindToCloseService = self._serviceBag:GetService(BindToCloseService)
	self._dataStorePromise = nil
	self._dataStorePromises = {}
	self._robloxDataStorePromise = nil
	self._customKey = nil
end

--[=[
	Returns the datastore for the current private-server ID, or "main" for a
	public server.

	@within PrivateServerDataStoreService
	@return Promise<DataStore>
]=]
function PrivateServerDataStoreService.PromiseDataStore(
	self: PrivateServerDataStoreService
): Promise.Promise<DataStore.DataStore>
	if self._dataStorePromise then
		return self._dataStorePromise
	end

	self._dataStorePromise = self:PromiseDataStoreForKey(self:_getKey())

	return self._dataStorePromise
end

--[=[
	Returns a datastore for a specific private-server ID. This permits a source
	server to mark a newly reserved destination without changing the datastore
	used for its own session.

	@within PrivateServerDataStoreService
	@param key string
	@return Promise<DataStore>
]=]
function PrivateServerDataStoreService.PromiseDataStoreForKey(
	self: PrivateServerDataStoreService,
	key: string
): Promise.Promise<DataStore.DataStore>
	assert(t.string(key) and key ~= "", "Bad key")

	const existingPromise = self._dataStorePromises[key]
	if existingPromise then
		return existingPromise
	end

	const dataStorePromise = self:_promiseRobloxDataStore():Then(function(robloxDataStore)
		const dataStore = DataStore.new(robloxDataStore, key)
		self._maid:GiveTask(dataStore)

		if key == game.PrivateServerId and game.PrivateServerOwnerId ~= 0 then
			dataStore:Store("LastPrivateServerOwnerId", game.PrivateServerOwnerId)
		end

		self._maid:GiveTask(self._bindToCloseService:RegisterPromiseOnCloseCallback(function()
			return dataStore:Save()
		end))

		return dataStore
	end)
	self._dataStorePromises[key] = dataStorePromise

	return dataStorePromise
end

--[=[
	Overrides the private-server key before the datastore is first resolved.
	This is used by soft shutdown to write the marker for a newly reserved
	server once Roblox returns its private-server ID.

	@within PrivateServerDataStoreService
	@param customKey string
]=]
function PrivateServerDataStoreService.SetCustomKey(self: PrivateServerDataStoreService, customKey: string): ()
	assert(t.string(customKey) and customKey ~= "", "Bad customKey")
	assert(not self._dataStorePromise, "Cannot change key after datastore resolution")

	self._customKey = customKey
end

--[=[
	Injects the underlying Roblox datastore before it is first resolved.

	@within PrivateServerDataStoreService
	@param robloxDataStore DataStore
]=]
function PrivateServerDataStoreService.SetRobloxDataStore(self: PrivateServerDataStoreService, robloxDataStore: any): ()
	assert(DataStorePromises.isDataStore(robloxDataStore), "Bad robloxDataStore")
	assert(not self._robloxDataStorePromise, "Roblox datastore is already resolved")

	self._robloxDataStorePromise = Promise.resolved(robloxDataStore)
end

function PrivateServerDataStoreService._promiseRobloxDataStore(
	self: PrivateServerDataStoreService
): Promise.Promise<any>
	if not self._robloxDataStorePromise then
		self._robloxDataStorePromise =
			self._maid:GivePromise(DataStorePromises.promiseDataStore(DATASTORE_NAME, DATASTORE_SCOPE))
	end

	return self._robloxDataStorePromise
end

function PrivateServerDataStoreService._getKey(self: PrivateServerDataStoreService): string
	if self._customKey then
		return self._customKey
	end
	if game.PrivateServerId ~= "" then
		return game.PrivateServerId
	end

	return MAIN_SERVER_KEY
end

function PrivateServerDataStoreService.Destroy(self: PrivateServerDataStoreService): ()
	self._maid:DoCleaning()
end

return PrivateServerDataStoreService
