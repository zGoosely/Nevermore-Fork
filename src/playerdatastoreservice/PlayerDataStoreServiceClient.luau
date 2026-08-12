--!strict
--[=[
	Client-side mirror of [PlayerDataStoreService].

	Receives the full profile as one Squash buffer (`profileLoaded`) and then
	applies `valueChanged` deltas on top of it. The store is read-only with one
	exception: [PlayerDataStoreServiceClient.SetSetting] may ask the server to change a
	setting. Everything else is server-authoritative and has no setter.

	@class PlayerDataStoreServiceClient
	@client
]=]

const require = require("../Loader").load()

const Maid = require("Maid")
const Observable = require("Observable")
const ObservableMap = require("ObservableMap")
const PlayerDataStoreServiceNetwork = require("PlayerDataStoreServiceNetwork")
const PlayerDataStoreServiceProfile = require("PlayerDataStoreServiceProfile")
const PlayerDataStoreServiceUtils = require("PlayerDataStoreServiceUtils")
const Promise = require("Promise")
const Rx = require("Rx")
const ServiceBag = require("ServiceBag")
const Squash = require("Squash")
const TableUtils = require("TableUtils")
const t = require("t")

const PlayerDataStoreServiceClient = {}
PlayerDataStoreServiceClient.ServiceName = "PlayerDataStoreServiceClient"

type PendingValueChange = {
	name: string,
	value: any,
}

export type PlayerDataStoreServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,

		_data: ObservableMap.ObservableMap<string, any>,
		_dataPromise: Promise.Promise<any>,
		_hasLoadedProfile: boolean,
		_pendingValueChanges: { PendingValueChange },
		_profileData: PlayerDataStoreServiceProfile.ProfileDefinition,
	},
	{} :: typeof({ __index = PlayerDataStoreServiceClient })
))

function PlayerDataStoreServiceClient.Init(self: PlayerDataStoreServiceClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	self._data = self._maid:Add(ObservableMap.new())
	self._dataPromise = self._maid:GivePromise(Promise.new())
	self._hasLoadedProfile = false
	self._pendingValueChanges = {}
	self._profileData = PlayerDataStoreServiceProfile.Lock()
end

function PlayerDataStoreServiceClient.Start(self: PlayerDataStoreServiceClient)
	const function applyValueChange(value: PendingValueChange)
		PlayerDataStoreServiceUtils.writeObservableValuePath(self._data, value.name, value.value)
	end

	PlayerDataStoreServiceNetwork.packets.profileLoaded.listen(function(value: { data: buffer, hiddenKeys: { string } })
		const cursor = Squash.frombuffer(value.data)
		const success, profile = pcall(self._profileData.Schema.des, cursor)

		if not success then
			warn(`[PlayerDataStoreServiceClient] - Failed to deserialize profile ({profile})`)
			return
		end

		-- Hidden keys ride along blanked out to keep the buffer schema-shaped,
		-- so drop them rather than surface a placeholder as if it were real
		for _, keyName in value.hiddenKeys do
			PlayerDataStoreServiceUtils.writeValuePath(profile, keyName, nil)
		end

		for keyName, keyValue in profile do
			self._data:Set(keyName, keyValue)
		end

		-- ByteNet may deliver deltas queued during profile setup before this full
		-- snapshot has reached the client. Applying those deltas to an empty map can
		-- manufacture an incomplete root whose shape conflicts with a later nested
		-- write. Install the snapshot first, then replay deltas in receive order.
		self._hasLoadedProfile = true
		for _, pendingValueChange in self._pendingValueChanges do
			applyValueChange(pendingValueChange)
		end
		table.clear(self._pendingValueChanges)

		self._dataPromise:Resolve(self:GetData())
	end)

	PlayerDataStoreServiceNetwork.packets.valueChanged.listen(function(value: PendingValueChange)
		if not self._hasLoadedProfile then
			table.insert(self._pendingValueChanges, value)
			return
		end

		applyValueChange(value)
	end)
end

--[=[
	Resolves with the local player's profile data once the server has sent it.
	Resolves immediately if it has already arrived.

	@within PlayerDataStoreServiceClient
	@return Promise<any>
]=]
function PlayerDataStoreServiceClient.PromiseDataStore(self: PlayerDataStoreServiceClient): Promise.Promise<any>
	return Promise.resolved(self._dataPromise)
end

--[=[
	Returns a copy of the currently replicated profile data.

	@within PlayerDataStoreServiceClient
	@return any
]=]
function PlayerDataStoreServiceClient.GetData(self: PlayerDataStoreServiceClient): any
	return TableUtils.assign({}, self._data :: any)
end

--[=[
	Gets a value out of the replicated profile. Supports nested dot-separated
	paths.

	```lua
	PlayerDataStoreServiceClient:GetValue("Coins")
	PlayerDataStoreServiceClient:GetValue("Inventory.MaxItems")
	```

	@within PlayerDataStoreServiceClient
	@param keyName string
	@return any
]=]
function PlayerDataStoreServiceClient.GetValue<T>(self: PlayerDataStoreServiceClient, keyName: string): T?
	assert(t.string(keyName), "Bad keyName")

	return PlayerDataStoreServiceUtils.readObservableValuePath(self._data, keyName) :: T?
end

--[=[
	Observes the whole replicated profile, firing with the current data and
	again on every change.

	@within PlayerDataStoreServiceClient
	@return Observable<any>
]=]
function PlayerDataStoreServiceClient.Observe(self: PlayerDataStoreServiceClient): Observable.Observable<any>
	return Observable.new(function(sub)
		const maid = Maid.new()

		const function update()
			sub:Fire(self:GetData())
		end

		maid:GiveTask(self._data.KeyValueChanged:Connect(update))
		update()

		return maid
	end)
end

--[=[
	Observes a single value in the replicated profile. Supports nested
	dot-separated paths.

	```lua
	PlayerDataStoreServiceClient:ObserveAtKey("Coins")
	PlayerDataStoreServiceClient:ObserveAtKey("Inventory.MaxItems")
	```

	@within PlayerDataStoreServiceClient
	@param keyName string
	@return Observable<any>
]=]
function PlayerDataStoreServiceClient.ObserveAtKey<T>(
	self: PlayerDataStoreServiceClient,
	keyName: string
): Observable.Observable<T?>
	assert(t.string(keyName), "Bad keyName")

	const rootKey, path = PlayerDataStoreServiceUtils.splitValuePath(keyName)
	if not path then
		return self._data:ObserveAtKey(rootKey) :: any
	end

	return self._data:ObserveAtKey(rootKey):Pipe({
		Rx.map(function(rootValue: any): any
			return PlayerDataStoreServiceUtils.readValuePath(rootValue, path)
		end) :: any,
		Rx.distinct() :: any,
	}) :: any
end

--[=[
	Gets a setting. Settings are the keys of the profile template's Settings
	table.

	```lua
	PlayerDataStoreServiceClient:GetSetting("MusicEnabled")
	```

	@within PlayerDataStoreServiceClient
	@param name string
	@return any
]=]
function PlayerDataStoreServiceClient.GetSetting<T>(self: PlayerDataStoreServiceClient, name: string): T?
	assert(PlayerDataStoreServiceUtils.isSettingName(name), `Bad name, {tostring(name)} is not a setting`)

	return self:GetValue(PlayerDataStoreServiceUtils.getSettingPath(name)) :: T?
end

--[=[
	Asks the server to change a setting, and applies it locally straight away.

	The local store updates before this returns, so observers have already fired
	with the new value by the time the request reaches the server. The server has
	the final say: if it refuses, it sends the real value back and the local store
	snaps to it through the ordinary replication path. There is no acknowledgement
	and no rejection signal -- observing the setting is how you find out.

	Only settings whose default is a primitive can be set from here. Errors rather
	than no-ops on a bad name or value, since an honest caller is checked against
	the same rules the server uses and so should never be refused.

	```lua
	PlayerDataStoreServiceClient:SetSetting("MusicEnabled", false)
	```

	@within PlayerDataStoreServiceClient
	@param name string
	@param value any
]=]
function PlayerDataStoreServiceClient.SetSetting(self: PlayerDataStoreServiceClient, name: string, value: any)
	assert(
		PlayerDataStoreServiceUtils.isWritableSettingName(name),
		`Bad name, {tostring(name)} is not a writable setting`
	)
	assert(PlayerDataStoreServiceUtils.isValidSettingValue(name, value), `Bad value for setting {name}`)

	const path = PlayerDataStoreServiceUtils.getSettingPath(name)
	const rootKey = PlayerDataStoreServiceUtils.splitValuePath(path)
	assert(self._data:ContainsKey(rootKey), "Profile hasn't loaded")

	if PlayerDataStoreServiceUtils.readObservableValuePath(self._data, path) == value then
		return
	end

	-- Applied first, sent second. The wire cannot beat this either way -- ByteNet
	-- batches sends to the next heartbeat -- but doing it in this order is what
	-- makes "observers have fired by the time this returns" a guarantee.
	PlayerDataStoreServiceUtils.writeObservableValuePath(self._data, path, value)
	PlayerDataStoreServiceNetwork.packets.settingRequested.send({
		name = name,
		value = value,
	})
end

--[=[
	Observes a setting, firing with the current value and again on every change,
	including when the server rolls back a change it refused.

	```lua
	PlayerDataStoreServiceClient:ObserveSetting("MusicEnabled")
	```

	@within PlayerDataStoreServiceClient
	@param name string
	@return Observable<any>
]=]
function PlayerDataStoreServiceClient.ObserveSetting<T>(
	self: PlayerDataStoreServiceClient,
	name: string
): Observable.Observable<T?>
	assert(PlayerDataStoreServiceUtils.isSettingName(name), `Bad name, {tostring(name)} is not a setting`)

	return self:ObserveAtKey(PlayerDataStoreServiceUtils.getSettingPath(name))
end

function PlayerDataStoreServiceClient.Destroy(self: PlayerDataStoreServiceClient)
	self._maid:Destroy()
end

return PlayerDataStoreServiceClient
