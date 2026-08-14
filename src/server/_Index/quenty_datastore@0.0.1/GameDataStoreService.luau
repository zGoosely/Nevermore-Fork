--!strict
--[=[
	Provides a frequently synchronized datastore for game-wide server state.

	@class GameDataStoreService
	@server
]=]
const BindToCloseService = require("@game/ReplicatedStorage/Packages/BindToCloseService")
const DataStore = require("./DataStore")
const DataStorePromises = require("./DataStorePromises")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

const DATASTORE_NAME = "GameDataStore"
const DATASTORE_SCOPE = "Version1"
const DEFAULT_KEY = "version1"
const AUTO_SAVE_TIME_SECONDS = 5

const GameDataStoreService = {}
GameDataStoreService.ServiceName = "GameDataStoreService"
GameDataStoreService.ServerOnly = true

export type GameDataStoreService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_bindToCloseService: BindToCloseService.BindToCloseService,
		_dataStorePromise: Promise.Promise<DataStore.DataStore>?,
		_robloxDataStorePromise: Promise.Promise<any>?,
		_key: string?,
	},
	{} :: typeof({ __index = GameDataStoreService })
))

function GameDataStoreService.Init(self: GameDataStoreService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._bindToCloseService = self._serviceBag:GetService(BindToCloseService)
	self._dataStorePromise = nil
	self._robloxDataStorePromise = nil
	self._key = nil
end

--[=[
	Injects the underlying Roblox datastore before it is first resolved.

	@within GameDataStoreService
	@param robloxDataStore DataStore
]=]
function GameDataStoreService.SetRobloxDataStore(self: GameDataStoreService, robloxDataStore: any): ()
	assert(DataStorePromises.isDataStore(robloxDataStore), "Bad robloxDataStore")
	assert(not self._robloxDataStorePromise, "Roblox datastore is already resolved")

	self._robloxDataStorePromise = Promise.resolved(robloxDataStore)
end

--[=[
	Returns the game-wide server-state datastore.

	@within GameDataStoreService
	@return Promise<DataStore>
]=]
function GameDataStoreService.PromiseDataStore(self: GameDataStoreService): Promise.Promise<DataStore.DataStore>
	if self._dataStorePromise then
		return self._dataStorePromise
	end

	self._dataStorePromise = self:_promiseRobloxDataStore():Then(function(robloxDataStore)
		const dataStore = DataStore.new(robloxDataStore, self:_getKey())
		dataStore:SetSyncOnSave(true)
		dataStore:SetAutoSaveTimeSeconds(AUTO_SAVE_TIME_SECONDS)
		self._maid:GiveTask(dataStore)

		self._maid:GiveTask(self._bindToCloseService:RegisterPromiseOnCloseCallback(function()
			return dataStore:Save()
		end))

		return dataStore
	end)

	return self._dataStorePromise
end

--[=[
	Sets the game-wide storage key before the datastore is first resolved.

	@within GameDataStoreService
	@param key string
]=]
function GameDataStoreService.SetDataStoreKey(self: GameDataStoreService, key: string): ()
	assert(t.string(key) and key ~= "", "Bad key")
	assert(not self._dataStorePromise, "Cannot change key after datastore resolution")

	self._key = key
end

function GameDataStoreService._promiseRobloxDataStore(self: GameDataStoreService): Promise.Promise<any>
	if not self._robloxDataStorePromise then
		self._robloxDataStorePromise =
			self._maid:GivePromise(DataStorePromises.promiseDataStore(DATASTORE_NAME, DATASTORE_SCOPE))
	end

	return self._robloxDataStorePromise
end

function GameDataStoreService._getKey(self: GameDataStoreService): string
	return self._key or DEFAULT_KEY
end

function GameDataStoreService.Destroy(self: GameDataStoreService): ()
	self._maid:DoCleaning()
end

return GameDataStoreService
