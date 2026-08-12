--!strict
--[=[
	Owns ProfileStore sessions for players in live gameplay servers and
	replicates approved profile data to [PlayerDataStoreServiceClient].

	@class PlayerDataStoreService
	@server
]=]

const HttpService = game:GetService("HttpService")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const require = require("../Loader").load()

const AsyncSemaphore = require("AsyncSemaphore")
const AttributeUtils = require("AttributeUtils")
const BindToCloseService = require("BindToCloseService")
const CmdrService = require("CmdrService")
const ErrorReportingUtils = require("ErrorReportingUtils")
const Maid = require("Maid")
const Observable = require("Observable")
const ObservableMap = require("ObservableMap")
const ObservableSet = require("ObservableSet")
const PlayerDataStoreServiceNetwork = require("PlayerDataStoreServiceNetwork")
const PlayerDataStoreServiceProfile = require("PlayerDataStoreServiceProfile")
const PlayerDataStoreServiceUtils = require("PlayerDataStoreServiceUtils")
const PrivateServerDataStoreService = require("PrivateServerDataStoreService")
const ProfileStore = require("ProfileStore")
const Promise = require("Promise")
const PromiseMaidUtils = require("PromiseMaidUtils")
const PromiseUtils = require("PromiseUtils")
const Rx = require("Rx")
const RxPlayerUtils = require("RxPlayerUtils")
const ServiceBag = require("ServiceBag")
const Signal = require("Signal")
const SoftShutdownServiceUtils = require("SoftShutdownServiceUtils")
const Squash = require("Squash")
const TableUtils = require("TableUtils")
const t = require("t")

const PROFILE_NAME = "Default"
const PROFILE_VERSION = 1

-- A soft shutdown can return a full server at once. Keep that burst below the
-- ProfileStore/Roblox request queue without making every player load serially.
const MAX_CONCURRENT_PROFILE_LOADS = 5

-- How long a transaction callback may run before it loses its locks. Generous:
-- a callback that has not decided by now is never going to.
const TRANSACTION_TIMEOUT_SECONDS = 10

-- Kept under Roblox's 30 second BindToClose budget, so a profile that never
-- reports its save cannot hold the shutdown open until it is killed anyway
const SAVE_TIMEOUT_SECONDS = 20

const PlayerDataStoreService = {}
PlayerDataStoreService.ServiceName = "PlayerDataStoreService"
PlayerDataStoreService.ServerOnly = true

export type PlayerDataStoreService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_bindToCloseService: BindToCloseService.BindToCloseService,
		_cmdrService: CmdrService.CmdrService,
		_privateServerDataStoreService: PrivateServerDataStoreService.PrivateServerDataStoreService,
		_profileLoadSemaphore: AsyncSemaphore.AsyncSemaphore,

		_attributeKeys: ObservableSet.ObservableSet<string>,
		_hiddenKeys: ObservableSet.ObservableSet<string>,
		_profileList: ObservableMap.ObservableMap<Player, ProfileStore.Profile<any>>,
		_customReplicators: ObservableMap.ObservableMap<string, (Player, any, string) -> ()>,
		_valueChanged: Signal.Signal<Player, string, any>,

		_lockedPlayers: { [Player]: true },
		_playerUnlocked: Signal.Signal<>,
		_profileData: PlayerDataStoreServiceProfile.ProfileDefinition,
		_canLoadProfiles: boolean?,

		DataStore: ProfileStore.ProfileStore<any>,
	},
	{} :: typeof({ __index = PlayerDataStoreService })
))

function PlayerDataStoreService.Init(self: PlayerDataStoreService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._bindToCloseService = self._serviceBag:GetService(BindToCloseService)
	self._cmdrService = self._serviceBag:GetService(CmdrService)
	self._privateServerDataStoreService = self._serviceBag:GetService(PrivateServerDataStoreService)
	self._profileLoadSemaphore = self._maid:Add(AsyncSemaphore.new(MAX_CONCURRENT_PROFILE_LOADS))

	self._attributeKeys = self._maid:Add(ObservableSet.new())
	self._hiddenKeys = self._maid:Add(ObservableSet.new())
	self._profileList = self._maid:Add(ObservableMap.new())
	self._customReplicators = self._maid:Add(ObservableMap.new())
	self._valueChanged = self._maid:Add(Signal.new())

	self._lockedPlayers = setmetatable({}, { __mode = "k" }) :: any
	self._playerUnlocked = self._maid:Add(Signal.new())
	self._profileData = PlayerDataStoreServiceProfile.Lock()
	self._canLoadProfiles = nil

	self.DataStore = ProfileStore.New(self:GetStoreNameAndVersion(), TableUtils.deepCopy(self._profileData.Template))
end

function PlayerDataStoreService.Start(self: PlayerDataStoreService): ()
	-- Swapped before the subscription below, which starts loading profiles the
	-- moment it runs -- any player already present would otherwise load against
	-- the live store and only then get moved onto the mock
	if RunService:IsStudio() then
		warn(`[PlayerDataStoreService] - Using Mock DataStore`)
		self.DataStore = self.DataStore.Mock :: any
	end

	local function getCommandProfile(player: Player): (boolean, any)
		const loaded, profileOrError = self:PromiseProfile(player):Yield()
		if not loaded then
			return false, tostring(profileOrError)
		end

		const profile = profileOrError :: ProfileStore.Profile<any>
		if not profile:IsActive() then
			return false, `Profile is not active for {player.Name}`
		end
		return true, profile
	end

	local function encodeCommandValue(value: any): (boolean, string)
		const encoded, resultOrError = (pcall :: any)(HttpService.JSONEncode, HttpService, value)
		if not encoded then
			return false, `Data cannot be displayed as JSON: {resultOrError}`
		end
		return true, resultOrError :: string
	end

	local function decodeCommandValue(serializedValue: string): any
		const decoded, value = (pcall :: any)(HttpService.JSONDecode, HttpService, serializedValue)
		return if decoded then value else serializedValue
	end

	self._cmdrService:RegisterCommand({
		Name = "read-data",
		Description = "Reads a player's full profile or a dot-separated data path.",
		Group = "DefaultAdmin",
		Args = {
			{
				Type = "player",
				Name = "player",
				Description = "The player whose data should be read.",
			},
			{
				Type = "string",
				Name = "path",
				Description = "An optional dot-separated path, such as Inventory.Items.",
				Optional = true,
			},
		},
		Run = function(_, player: Player, path: string?)
			const loaded, profileOrError = getCommandProfile(player)
			if not loaded then
				return `Could not read {player.Name}'s data: {tostring(profileOrError)}.`
			end
			const profile = profileOrError :: ProfileStore.Profile<any>
			const hasPath = type(path) == "string" and path ~= ""
			const value = if hasPath
				then PlayerDataStoreServiceUtils.readValuePath(profile.Data, path :: string)
				else profile.Data
			if value == nil then
				return `{player.Name}.{path} = nil (path does not exist)`
			end

			const encoded, encodedValue = encodeCommandValue(value)
			if not encoded then
				return `Could not read {player.Name}.{if hasPath then path else "Data"}: {encodedValue}.`
			end
			return `{player.Name}.{if hasPath then path else "Data"} = {encodedValue}`
		end,
	})

	self._cmdrService:RegisterCommand({
		Name = "write-data",
		Description = "Overwrites an existing data path with JSON or a bare string.",
		Group = "DefaultAdmin",
		Args = {
			{
				Type = "player",
				Name = "player",
				Description = "The player whose data should be changed.",
			},
			{
				Type = "string",
				Name = "path",
				Description = "The existing dot-separated path to overwrite.",
			},
			{
				Type = "string",
				Name = "newValue",
				Description = "JSON for typed values and tables, or unquoted text for a string.",
			},
		},
		Run = function(_, player: Player, path: string, serializedValue: string)
			const newValue = decodeCommandValue(serializedValue)
			if newValue == nil then
				return "Could not write data: JSON null cannot be written to profile data."
			end

			const loaded, profileOrError = getCommandProfile(player)
			if not loaded then
				return `Could not write {player.Name}.{path}: {tostring(profileOrError)}.`
			end
			const profile = profileOrError :: ProfileStore.Profile<any>
			const candidateData = TableUtils.deepCopy(profile.Data)
			const wroteValue, writeError =
				pcall(PlayerDataStoreServiceUtils.writeValuePath, candidateData, path, newValue)
			if not wroteValue then
				return `Could not write {player.Name}.{path}: {tostring(writeError)}.`
			end

			const cursor = Squash.cursor()
			const isValid, validationError = pcall(self._profileData.Schema.ser, cursor, candidateData)
			if not isValid then
				return `Could not write {player.Name}.{path}: value does not match {PlayerDataStoreServiceProfile.GetName()}.Schema ({tostring(
					validationError
				)}).`
			end
			const validationCursor = Squash.frombuffer(Squash.tobuffer(cursor))
			const decoded, schemaDataOrError = pcall(self._profileData.Schema.des, validationCursor)
			if not decoded then
				return `Could not write {player.Name}.{path}: {PlayerDataStoreServiceProfile.GetName()}.Schema could not read the validated value ({tostring(
					schemaDataOrError
				)}).`
			end
			if PlayerDataStoreServiceUtils.readValuePath(schemaDataOrError, path) == nil then
				return `Could not write {player.Name}.{path}: path is not represented by {PlayerDataStoreServiceProfile.GetName()}.Schema.`
			end

			const resolvedValue = PlayerDataStoreServiceUtils.readValuePath(candidateData, path)
			const setValue, setError = pcall(function()
				self:SetValue(player, path, resolvedValue)
			end)
			if not setValue then
				return `Could not write {player.Name}.{path}: {tostring(setError)}.`
			end
			const saved, saveError = self:SaveProfile(player):Yield()
			if not saved then
				return `Updated {player.Name}.{path} in memory, but the immediate save failed: {tostring(saveError)}.`
			end

			const encoded, encodedValue = encodeCommandValue(resolvedValue)
			if not encoded then
				return `Set {player.Name}.{path}, but could not display the new value: {encodedValue}.`
			end
			return `Set {player.Name}.{path} = {encodedValue}`
		end,
	})

	self._cmdrService:RegisterCommand({
		Name = "reset-data",
		Description = "Deletes a player's profile and disconnects them so defaults load on rejoin.",
		Group = "DefaultAdmin",
		Args = {
			{
				Type = "player",
				Name = "player",
				Description = "The player whose profile should be reset.",
			},
		},
		Run = function(_, player: Player)
			const loaded, profileOrError = getCommandProfile(player)
			if not loaded then
				return `Could not reset {player.Name}'s data: {tostring(profileOrError)}.`
			end
			const reset, resetError = self:DeleteProfileAsync(player):Yield()
			if not reset then
				return `Could not reset {player.Name}'s data: {tostring(resetError)}.`
			end

			return `Reset {player.Name}'s data. They must rejoin to load the defaults.`
		end,
	})

	self._maid:GiveTask(self._bindToCloseService:RegisterPromiseOnCloseCallback(function()
		return self:SaveAllProfilesAsync()
	end))

	self._maid
		:GivePromise(SoftShutdownServiceUtils.promiseIsLobby(self._privateServerDataStoreService))
		:Then(function(isLobby: boolean)
			self._canLoadProfiles = not isLobby
			if not isLobby then
				self:_startLoadingProfiles()
			end
		end)
		:Catch(function(errorMessage: any)
			self._canLoadProfiles = false
			warn(
				`[PlayerDataStoreService] - Disabled profile loading because the waiting-server check failed: {errorMessage}`
			)
		end)

	PlayerDataStoreServiceNetwork.packets.settingRequested.listen(
		function(payload: { name: string, value: unknown }, player: Player?)
			const profile = self:GetProfile(player :: Player)
			if not profile or not profile:IsActive() then
				return
			end

			if not PlayerDataStoreServiceUtils.isWritableSettingName(payload.name) then
				return
			end

			const path = PlayerDataStoreServiceUtils.getSettingPath(payload.name)
			const currentValue = PlayerDataStoreServiceUtils.readValuePath(profile.Data, path)
			if currentValue == nil then
				return
			end

			if not PlayerDataStoreServiceUtils.isValidSettingValue(payload.name, payload.value) then
				-- Never SetValue here. It returns early when the value is unchanged,
				-- which a refusal always is, so nothing would be sent and the client
				-- would keep believing its own guess forever.
				self:ReplicateValue(player :: Player, path, currentValue)
				return
			end

			-- Roll back the same way when a profile Validator refuses the value, so
			-- SetValue never asserts on a client-driven write and the client is
			-- corrected instead of left believing its own guess.
			if
				PlayerDataStoreServiceUtils.getWriteValidationError(
					self._profileData.Validators,
					profile.Data,
					path,
					payload.value
				)
			then
				self:ReplicateValue(player :: Player, path, currentValue)
				return
			end

			self:SetValue(player :: Player, path, payload.value)
		end
	)
end

--[=[
	Returns the current name and version of the DataStore

	@within PlayerDataStoreService
	@returns string, string
]=]
function PlayerDataStoreService.GetStoreNameAndVersion(self: PlayerDataStoreService)
	const storeName = self._profileData.StoreName or PROFILE_NAME
	const storeVersion = self._profileData.StoreVersion or PROFILE_VERSION
	assert(type(storeName) == "string" and storeName ~= "", "Bad profile StoreName")
	assert(type(storeVersion) == "number" and storeVersion >= 1 and storeVersion % 1 == 0, "Bad profile StoreVersion")
	return `{storeName}_{storeVersion}`
end

--[=[
	Adds a custom replicator for a profile path. The callback replaces ordinary
	PlayerDataStoreService replication for that path and all of its descendants. It also runs
	for hidden paths, allowing a feature service to expose a narrower projection of
	the hidden server data.

	The callback receives the player, changed value, and exact changed path.

	@within PlayerDataStoreService
	@param keyName string
	@param callback (Player, any, string) -> ()
	@returns string
]=]
function PlayerDataStoreService.AddReplicator(
	self: PlayerDataStoreService,
	keyName: string,
	callback: (Player, any, string) -> ()
): string
	assert(t.string(keyName), "Bad keyName")
	assert(t.callback(callback), "Bad callback")
	self._customReplicators:Set(keyName, callback)

	return keyName
end

--[=[
	Marks a key as hidden from ordinary PlayerDataStoreService replication. Hidden keys live
	in the player's profile and save like any other value. The client is sent a
	blanked-out placeholder of the same shape, and later changes are withheld unless
	a feature installs a narrower projection with [PlayerDataStoreService.AddReplicator].

	Set hidden keys before any profile loads. Hiding a key that has already
	replicated does not retract the copy the client is holding.

	```lua
	PlayerDataStoreService:SetHiddenKey("PurchaseHistory")
	PlayerDataStoreService:SetHiddenKey("Inventory.SecretSeed")
	```

	@within PlayerDataStoreService
	@param keyName string
	@returns string
]=]
function PlayerDataStoreService.SetHiddenKey(self: PlayerDataStoreService, keyName: string): string
	assert(t.string(keyName), "Bad keyName")
	assert(not self._attributeKeys:Contains(keyName), `Cannot hide {keyName}, it is an attribute key`)

	-- Settings have to replicate: a refused [PlayerDataStoreServiceClient.SetSetting] is
	-- rolled back by replicating the real value, and ReplicateValue sends nothing
	-- for a hidden key, so the client would keep its own guess forever. Rooted
	-- rather than exact, since hiding "Settings" and hiding "Settings.Foo" break
	-- it in different ways -- and the second would push a hidden value to a client
	-- that was sent a blanked root.
	assert(
		PlayerDataStoreServiceUtils.splitValuePath(keyName) ~= PlayerDataStoreServiceUtils.getSettingsKey(),
		`Cannot hide {keyName}, settings must replicate`
	)

	self._hiddenKeys:Add(keyName)

	return keyName
end

--[=[
	Unmarks a hidden key. The value replicates again from its next change
	onwards -- the client is not backfilled with what it missed.

	@within PlayerDataStoreService
	@param keyName string
	@returns boolean
]=]
function PlayerDataStoreService.RemoveHiddenKey(self: PlayerDataStoreService, keyName: string): boolean
	assert(t.string(keyName), "Bad keyName")

	return self._hiddenKeys:Remove(keyName)
end

--[=[
	Returns whether a key is hidden from the client.

	@within PlayerDataStoreService
	@param keyName string
	@returns boolean
]=]
function PlayerDataStoreService.IsHiddenKey(self: PlayerDataStoreService, keyName: string): boolean
	assert(t.string(keyName), "Bad keyName")

	for _, hiddenKey in self._hiddenKeys:GetList() do
		if PlayerDataStoreServiceUtils.valuePathsOverlap(hiddenKey, keyName) then
			return true
		end
	end

	return false
end

--[=[
	Marks a key as an attribute key. The value is mirrored onto the Player
	instance as an attribute of the same name, both for profiles already loaded
	and for every profile that loads afterwards, and is kept in sync on change.

	The key must be a valid attribute name, which rules out the dot-separated
	paths [PlayerDataStoreService.SetValue] accepts. Note that attributes replicate to every
	client, so an attribute key cannot also be hidden.

	```lua
	PlayerDataStoreService:SetAttributeKey("Level")
	```

	@within PlayerDataStoreService
	@param keyName string
	@returns string
]=]
function PlayerDataStoreService.SetAttributeKey(self: PlayerDataStoreService, keyName: string): string
	assert(t.string(keyName), "Bad keyName")
	assert(AttributeUtils.isValidAttributeName(keyName), `Bad keyName, {keyName} is not a valid attribute name`)
	assert(not self._hiddenKeys:Contains(keyName), `Cannot set attribute key {keyName}, it is a hidden key`)

	self._attributeKeys:Add(keyName)

	for _, player in self._profileList:GetKeyList() do
		const profile = self._profileList:Get(player)

		if profile and profile:IsActive() then
			AttributeUtils.setAttribute(player, keyName, (profile.Data :: any)[keyName])
		end
	end

	return keyName
end

--[=[
	Unmarks an attribute key and clears the attribute from every loaded player.
	The underlying value stays in the profile.

	@within PlayerDataStoreService
	@param keyName string
	@returns boolean
]=]
function PlayerDataStoreService.RemoveAttributeKey(self: PlayerDataStoreService, keyName: string): boolean
	assert(t.string(keyName), "Bad keyName")

	if not self._attributeKeys:Remove(keyName) then
		return false
	end

	for _, player in self._profileList:GetKeyList() do
		player:SetAttribute(keyName, nil)
	end

	return true
end

--[=[
	Returns whether a key is mirrored onto the Player instance as an attribute.

	@within PlayerDataStoreService
	@param keyName string
	@returns boolean
]=]
function PlayerDataStoreService.IsAttributeKey(self: PlayerDataStoreService, keyName: string): boolean
	assert(t.string(keyName), "Bad keyName")

	return self._attributeKeys:Contains(keyName)
end

--[=[
	Replicates a specified value to a certain client

	@within PlayerDataStoreService
	@param player Player
	@param keyName string
	@param keyValue any
	@returns boolean
]=]
function PlayerDataStoreService.ReplicateValue(
	self: PlayerDataStoreService,
	player: Player,
	keyName: string,
	keyValue: any
): boolean
	assert(self._profileList:Get(player), "Player data hasn't loaded")
	assert(t.string(keyName), "Bad keyName")
	assert(t.any(keyValue), "Bad keyValue")

	if self._attributeKeys:Contains(keyName) then
		AttributeUtils.setAttribute(player, keyName, keyValue)
	end

	-- Fired before the hidden-key check: hiding a key withholds it from the
	-- client, but it is still the player's data and still observable here
	self._valueChanged:Fire(player, keyName, keyValue)

	-- Prefer the most specific registered ancestor. This lets a feature own one
	-- branch while still receiving path-level writes beneath it.
	local customReplicator = self._customReplicators:Get(keyName)
	local customReplicatorPathLength = if customReplicator then #keyName else 0
	if not customReplicator then
		for replicatorPath, candidate in self._customReplicators do
			if
				string.sub(keyName, 1, #replicatorPath + 1) == replicatorPath .. "."
				and #replicatorPath > customReplicatorPathLength
			then
				customReplicator = candidate
				customReplicatorPathLength = #replicatorPath
			end
		end
	end

	if customReplicator then
		const success, resultOrErr = (pcall :: any)(function(...)
			return customReplicator(...)
		end, player, keyValue, keyName)

		if not success then
			warn(`[PlayerDataStoreService] - Failed while replicating {keyName:upper()} ({resultOrErr})`)
			return false
		end

		return true
	end

	if self:IsHiddenKey(keyName) then
		return true
	end

	PlayerDataStoreServiceNetwork.packets.valueChanged.sendTo({
		name = keyName,
		value = keyValue,
	}, player)

	return true
end

--[=[
	Gets a players profile if it exists

	@within PlayerDataStoreService
	@param player Player
	@returns ProfileStore.Profile<any>?
]=]
function PlayerDataStoreService.GetProfile(self: PlayerDataStoreService, player: Player): ProfileStore.Profile<any>?
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self._profileList:Get(player) or nil
end

--[=[
	Waits for a player's profile, resolving as soon as it is loaded.

	Only ever waits -- unlike [PlayerDataStoreService.LoadProfileAsync] it never starts a
	session, so it is what you want from anything that merely needs the profile
	rather than owns loading it. [PlayerDataStoreService.Start] does the loading.

	Rejects if the player leaves first, so a caller cannot be left waiting on a
	profile that is never coming.

	```lua
	PlayerDataStoreService:PromiseProfile(player):Then(function(profile)
		print(profile.Data.Coins)
	end)
	```

	@within PlayerDataStoreService
	@param player Player
	@returns Promise<ProfileStore.Profile<any>>
]=]
function PlayerDataStoreService.PromiseProfile(self: PlayerDataStoreService, player: Player): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player), "Bad player")

	const profile = self:GetProfile(player)
	if profile then
		return Promise.resolved(profile)
	end
	if self._canLoadProfiles == false then
		return Promise.rejected("Player profile loading is disabled for this server")
	end

	const promise = Promise.new()

	-- whilePromise owns the listeners for exactly as long as the promise is
	-- pending. Keyed into the service maid on top of that, so a Destroy while we
	-- are still waiting takes them with it.
	self._maid[promise] = PromiseMaidUtils.whilePromise(promise, function(maid: Maid.Maid)
		maid:GiveTask(self._profileList:ObserveAtKey(player):Subscribe(function(profileValue: any)
			if profileValue then
				promise:Resolve(profileValue)
			end
		end))

		maid:GiveTask(Players.PlayerRemoving:Connect(function(removingPlayer: Player)
			if removingPlayer == player then
				promise:Reject("Player left before their profile loaded")
			end
		end))
	end)

	promise:Finally(function()
		self._maid[promise] = nil
	end)

	return promise
end

--[=[
	Loads a profile within a Promise

	@within PlayerDataStoreService
	@param player Player
	@returns Promise<any>
]=]
function PlayerDataStoreService.LoadProfileAsync(self: PlayerDataStoreService, player: Player): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player), "Bad player")

	if self._canLoadProfiles ~= true then
		return Promise.rejected("Player profile loading is not enabled for this server")
	end
	if SoftShutdownServiceUtils.isLobbyTeleportPlayer(player) then
		return Promise.rejected("Player arrived through a soft-shutdown waiting server")
	end

	if self._profileList:ContainsKey(player) then
		return Promise.resolved(self._profileList:Get(player))
	end

	return self._profileLoadSemaphore:RunAsync(function()
		return self:_loadProfileAsync(player)
	end)
end

--[=[
	Deletes a profile within a Promise

	@within PlayerDataStoreService
	@param player Player
	@returns Promise.Promise<any>
]=]
function PlayerDataStoreService.DeleteProfileAsync(self: PlayerDataStoreService, player: Player)
	assert(t.instanceIsA("Player")(player), "Bad player")

	return Promise.spawn(function(resolve, reject: (...any) -> ())
		const profile = assert(self:GetProfile(player))
		const userId = tostring(player.UserId)

		if profile ~= nil and profile:IsActive() then
			profile:EndSession()
		end

		const success, resultOrErr = pcall(function(userId)
			return self.DataStore:RemoveAsync(userId)
		end, userId)

		if success then
			resolve(success)
		else
			warn(`[PlayerDataStoreService] - Failed while deleting profile for {userId} ({resultOrErr})`)
			reject(resultOrErr)
		end
	end)
end

--[=[
	Flushes a player's profile to the DataStore, resolving once the write has
	actually landed rather than once it has been asked for.

	Resolves immediately for a player with no profile, or whose session already
	ended -- there is nothing to save and nothing to wait for.

	@within PlayerDataStoreService
	@param player Player
	@return Promise<()>
]=]
function PlayerDataStoreService.SaveProfile(self: PlayerDataStoreService, player: Player): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player), "Bad player")

	const profile = self:GetProfile(player)
	if not profile or not profile:IsActive() then
		return Promise.resolved()
	end

	-- Profile:Save() spawns the write and returns straight away, so the profile
	-- has to tell us when it is done. Connected first: the save can land before
	-- the call returns.
	const promise = PromiseUtils.fromSignal((profile :: any).OnAfterSave)
	profile:Save()

	return PromiseUtils.timeout(SAVE_TIMEOUT_SECONDS, promise):Catch(function(errorMessage)
		ErrorReportingUtils.logFatal(
			"Player profile save timed out or failed",
			ErrorReportingUtils.createFailureContext(errorMessage, {
				playerId = player.UserId,
				playerName = player.Name,
			})
		)
		return Promise.rejected(errorMessage)
	end)
end

--[=[
	Flushes every loaded profile, resolving once they have all landed. Registered
	as a [BindToCloseService] callback so a shutdown waits for it.

	@within PlayerDataStoreService
	@return Promise<()>
]=]
function PlayerDataStoreService.SaveAllProfilesAsync(self: PlayerDataStoreService): Promise.Promise<any>
	const promises = {}

	for _, player in self._profileList:GetKeyList() do
		table.insert(promises, self:SaveProfile(player))
	end

	return PromiseUtils.all(promises)
end

--[=[
	Gets a Value from within a players profile

	@within PlayerDataStoreService
	@param player Player
	@param keyName string
	@returns any
]=]
function PlayerDataStoreService.GetValue<T>(self: PlayerDataStoreService, player: Player, keyName: string): T?
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(t.string(keyName), "Bad keyName")

	const profile = self:GetProfile(player)
	assert(profile ~= nil and profile:IsActive(), "Bad profile")

	return PlayerDataStoreServiceUtils.readValuePath(profile.Data, keyName) :: T?
end

--[=[
	Observes a player's whole profile, firing with the current data and again on
	every change. Completes nothing when the player leaves -- it simply stops
	firing, since the profile is gone.

	Fires a deep copy, so mutating what you receive does not touch the profile.
	Prefer [PlayerDataStoreService.ObserveAtKey] unless you really need the whole thing.

	@within PlayerDataStoreService
	@param player Player
	@return Observable<any>
]=]
function PlayerDataStoreService.Observe(self: PlayerDataStoreService, player: Player): Observable.Observable<any>
	assert(t.instanceIsA("Player")(player), "Bad player")

	return Observable.new(function(sub)
		const maid = Maid.new()

		const function update()
			const profile = self:GetProfile(player)
			if profile then
				sub:Fire(TableUtils.deepCopy(profile.Data))
			end
		end

		maid:GiveTask(self._valueChanged:Connect(function(changedPlayer: Player)
			if changedPlayer == player then
				update()
			end
		end))

		update()

		return maid
	end)
end

--[=[
	Observes a single value in a player's profile, firing with the current value
	and again on every change. Supports nested dot-separated paths.

	```lua
	PlayerDataStoreService:ObserveAtKey(player, "Coins")
	PlayerDataStoreService:ObserveAtKey(player, "Inventory.MaxItems")
	```

	@within PlayerDataStoreService
	@param player Player
	@param keyName string
	@return Observable<any>
]=]
function PlayerDataStoreService.ObserveAtKey<T>(
	self: PlayerDataStoreService,
	player: Player,
	keyName: string
): Observable.Observable<T?>
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(t.string(keyName), "Bad keyName")

	const rootKey = PlayerDataStoreServiceUtils.splitValuePath(keyName)

	return Observable.new(function(sub)
		const maid = Maid.new()

		const function update()
			const profile = self:GetProfile(player)
			if profile then
				sub:Fire(PlayerDataStoreServiceUtils.readValuePath(profile.Data, keyName))
			end
		end

		maid:GiveTask(self._valueChanged:Connect(function(changedPlayer: Player, changedKey: string)
			-- Any write sharing our root key can move this path, in either
			-- direction: writing "Inventory" changes "Inventory.MaxItems", and
			-- writing "Inventory.MaxItems" changes "Inventory"
			if changedPlayer == player and PlayerDataStoreServiceUtils.splitValuePath(changedKey) == rootKey then
				update()
			end
		end))

		update()

		return maid
	end):Pipe({
		Rx.distinct() :: any,
	}) :: any
end

--[=[
	Sets a Value from within the players profile

	```lua
	PlayerDataStoreService:SetValue(player, "Coins", 100)
	PlayerDataStoreService:SetValue(player, "Inventory.MaxItems", 50)
	PlayerDataStoreService:SetValue(player, "Coins", function(coins)
		return coins + 100
	end)

	PlayerDataStoreService:SetValue(player, "Inventory.MaxItems", function(maxItems)
		return maxItems + 5
	end)
	```


	@within PlayerDataStoreService
	@param player Player
	@param keyName string
	@param keyValue any
	@returns any
]=]
function PlayerDataStoreService.SetValue(self: PlayerDataStoreService, player: Player, keyName: string, keyValue: any)
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(t.string(keyName), "Bad keyName")
	assert(t.any(keyValue), "Bad keyValue")

	const profile = self:GetProfile(player)
	assert(profile ~= nil and profile:IsActive(), "Bad profile")

	const currentValue = PlayerDataStoreServiceUtils.readValuePath(profile.Data, keyName)
	local newValue = nil

	const isCallback = t.callback(keyValue)
	if isCallback then
		newValue = keyValue(TableUtils.deepCopy(currentValue))
	else
		newValue = keyValue
	end

	if TableUtils.deepEquivalent(currentValue, newValue) then
		return newValue
	end

	const validationError = PlayerDataStoreServiceUtils.getWriteValidationError(
		self._profileData.Validators,
		profile.Data,
		keyName,
		newValue
	)
	assert(not validationError, `Bad keyValue for {keyName}: {validationError}`)

	PlayerDataStoreServiceUtils.writeValuePath(profile.Data, keyName, newValue)
	self:ReplicateValue(player, keyName, newValue)

	return newValue
end

--[=[
    Like SetValue but not limited to one value

	```lua
	PlayerDataStoreService:UpdateProfile(player, function(data)
		data.Coins += 100
		data.Level += 1

		return data
	end)
	```

    @within PlayerDataStoreService
    @param player Player
    @param callback (data) -> data
    @returns any
]=]
function PlayerDataStoreService.UpdateProfile(self: PlayerDataStoreService, player: Player, callback: (any) -> any)
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(t.callback(callback), "Bad callback")

	const profile = self:GetProfile(player)
	assert(profile ~= nil and profile:IsActive(), "Bad profile")

	const currentData = profile.Data
	const newData = callback(TableUtils.deepCopy(currentData))

	const validationError = PlayerDataStoreServiceUtils.getValidationError(self._profileData.Validators, newData)
	assert(not validationError, `Bad UpdateProfile result: {validationError}`)

	const pendingReplication = PlayerDataStoreServiceUtils.deepDiffPaths(currentData, newData)

	TableUtils.deepOverwrite(profile.Data, newData)
	for keyName, value in pendingReplication do
		self:ReplicateValue(player, keyName, value)
	end

	return newData
end

--[=[
	Applies one change across two profiles atomically -- a trade, a gift, buying
	something for somebody else. Either both profiles commit or neither does, so
	nothing can be created or destroyed in between.

	The callback receives a deep copy of each player's data and returns the two
	new versions. Return nothing to veto: the transaction rejects and neither
	profile is touched, which is how you turn down a trade that no longer adds up.

	```lua
	PlayerDataStoreService:TransactionAsync(seller, buyer, function(sellerData, buyerData)
		if buyerData.Coins < 100 or not table.find(sellerData.Inventory, itemId) then
			return -- veto, nothing is written
		end

		buyerData.Coins -= 100
		sellerData.Coins += 100
		table.remove(sellerData.Inventory, table.find(sellerData.Inventory, itemId))
		table.insert(buyerData.Inventory, itemId)

		return sellerData, buyerData
	end)
	```

	The callback may yield, but the less it does the better. It holds both
	players' transaction locks while it runs, it has TRANSACTION_TIMEOUT_SECONDS
	to finish before it is abandoned and the transaction rejects, and if either
	profile is written by anything else in the meantime the transaction rejects
	rather than commit on top of a stale read.

	@within PlayerDataStoreService
	@param playerA Player
	@param playerB Player
	@param callback (dataA, dataB) -> (dataA?, dataB?)
	@return Promise<any, any> -- Both players' new data
]=]
function PlayerDataStoreService.TransactionAsync(
	self: PlayerDataStoreService,
	playerA: Player,
	playerB: Player,
	callback: (any, any) -> (any?, any?)
): Promise.Promise<any>
	assert(t.instanceIsA("Player")(playerA), "Bad playerA")
	assert(t.instanceIsA("Player")(playerB), "Bad playerB")
	assert(playerA ~= playerB, "Cannot transact a player with themselves")
	assert(t.callback(callback), "Bad callback")

	return Promise.spawn(function(resolve, reject: (...any) -> ())
		const maid = Maid.new()

		-- Locked in a fixed order every time. Two transactions sharing a player
		-- can otherwise each hold the lock the other is waiting on
		const ordered = { playerA, playerB }
		table.sort(ordered, function(left: Player, right: Player)
			return left.UserId < right.UserId
		end)

		for _, player in ordered do
			while self._lockedPlayers[player] do
				self._playerUnlocked:Wait()
			end

			self._lockedPlayers[player] = true
		end

		-- Every exit below runs through the maid, so the locks come back whether
		-- we commit, veto, error or time out
		maid:GiveTask(function()
			for _, player in ordered do
				self._lockedPlayers[player] = nil
			end

			self._playerUnlocked:Fire()
		end)

		const profileA = self:GetProfile(playerA)
		const profileB = self:GetProfile(playerB)

		if not (profileA and profileA:IsActive() and profileB and profileB:IsActive()) then
			maid:DoCleaning()
			return reject("Both players must have an active profile")
		end

		-- Snapshots to compare against once the callback is done, so a write that
		-- lands while it yields cannot be silently overwritten
		const originalA = TableUtils.deepCopy(profileA.Data)
		const originalB = TableUtils.deepCopy(profileB.Data)

		-- The callback gets its own thread. Run inline, one that never returns
		-- would take this thread down with it and strand both locks for good
		const callbackPromise = maid:GivePromise(Promise.spawn(function(resolveCallback, rejectCallback)
			const ranCallback, resultA, resultB =
				pcall(callback, TableUtils.deepCopy(originalA), TableUtils.deepCopy(originalB))

			if not ranCallback then
				return rejectCallback(resultA)
			end

			resolveCallback(resultA, resultB)
		end))

		maid:GiveTask(task.delay(TRANSACTION_TIMEOUT_SECONDS, function()
			callbackPromise:Reject(`Transaction timed out after {TRANSACTION_TIMEOUT_SECONDS} seconds`)
		end))

		const success, newDataA, newDataB = callbackPromise:Yield()

		if not success then
			maid:DoCleaning()
			return reject(newDataA)
		end

		if newDataA == nil or newDataB == nil then
			maid:DoCleaning()
			return reject("Transaction vetoed by callback")
		end

		if not (profileA:IsActive() and profileB:IsActive()) then
			maid:DoCleaning()
			return reject("A profile ended its session during the transaction")
		end

		if
			not TableUtils.deepEquivalent(profileA.Data, originalA)
			or not TableUtils.deepEquivalent(profileB.Data, originalB)
		then
			maid:DoCleaning()
			return reject("A profile changed during the transaction")
		end

		const validationError = PlayerDataStoreServiceUtils.getValidationError(self._profileData.Validators, newDataA)
			or PlayerDataStoreServiceUtils.getValidationError(self._profileData.Validators, newDataB)
		if validationError then
			maid:DoCleaning()
			return reject(`Transaction produced invalid data ({validationError})`)
		end

		-- Commit. Nothing below yields, so no other code observes one profile
		-- written and the other not
		const changedA = PlayerDataStoreServiceUtils.getChangedRootKeys(originalA, newDataA)
		const changedB = PlayerDataStoreServiceUtils.getChangedRootKeys(originalB, newDataB)

		TableUtils.deepSync(profileA.Data, newDataA)
		TableUtils.deepSync(profileB.Data, newDataB)

		maid:DoCleaning()

		-- Replicated a whole root key at a time: a dot-separated path cannot say
		-- "this item left the array", and a trade is mostly removals
		for _, keyName in changedA do
			self:ReplicateValue(playerA, keyName, (profileA.Data :: any)[keyName])
		end

		for _, keyName in changedB do
			self:ReplicateValue(playerB, keyName, (profileB.Data :: any)[keyName])
		end

		resolve(newDataA, newDataB)
	end)
end

function PlayerDataStoreService._loadProfileAsync(self: PlayerDataStoreService, player: Player): Promise.Promise<any>
	if self._canLoadProfiles ~= true then
		return Promise.rejected("Player profile loading was disabled while waiting for a permit")
	end
	if SoftShutdownServiceUtils.isLobbyTeleportPlayer(player) then
		self._canLoadProfiles = false
		return Promise.rejected("Player arrived through a soft-shutdown waiting server")
	end
	if player.Parent ~= Players then
		return Promise.rejected("Player left before their profile could load")
	end
	if self._profileList:ContainsKey(player) then
		return Promise.resolved(self._profileList:Get(player))
	end

	const userId = player.UserId

	return Promise.spawn(function(resolve, reject: (...any) -> ())
		const profile = self.DataStore:StartSessionAsync(tostring(userId), {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})

		if not profile or player.Parent ~= Players then
			if not profile and player.Parent == Players then
				ErrorReportingUtils.logFatal(
					"Player profile failed to load",
					ErrorReportingUtils.createFailureContext("ProfileStore returned no active profile", {
						playerId = userId,
						playerName = player.Name,
					})
				)
			end
			if profile and profile:IsActive() then
				profile:EndSession()
			end
			if player.Parent == Players then
				player:Kick("Your data failed to load, please rejoin.")
			end
			reject("Player left or their profile failed to load")
			return
		end

		profile:AddUserId(userId)
		profile:Reconcile()
		profile.OnSessionEnd:Connect(function()
			-- We remove it from here because this function declares the profile officialy void
			-- Unlike our remove methods, this is most reliable
			self._profileList:Remove(player)

			if player.Parent == Players then
				ErrorReportingUtils.logFatal(
					"Active player profile session ended unexpectedly",
					ErrorReportingUtils.createFailureContext(
						"ProfileStore session ended while the player was connected",
						{
							playerId = userId,
							playerName = player.Name,
						}
					)
				)
				player:Kick("There has been an error with your data, please rejoin.")
			end
		end)

		self._profileList:Set(player, profile)
		resolve(profile)
	end)
end

function PlayerDataStoreService._startLoadingProfiles(self: PlayerDataStoreService): ()
	self._maid:Add(RxPlayerUtils.observePlayersBrio():Subscribe(function(brio)
		const maid, player = brio:ToMaidAndValue()
		if SoftShutdownServiceUtils.isLobbyTeleportPlayer(player) then
			self._canLoadProfiles = false
			return
		end

		maid:GivePromise(self:LoadProfileAsync(player))
			:Then(function(profile: ProfileStore.Profile<any>)
				maid:Add(function()
					if profile:IsActive() then
						profile:EndSession()
					end
				end)
				if player.Parent ~= Players or not profile:IsActive() then
					return
				end

				const hiddenKeys = self._hiddenKeys:GetList()
				const cursor = Squash.cursor()
				self._profileData.Schema.ser(
					cursor,
					PlayerDataStoreServiceUtils.getReplicatedData(profile.Data, hiddenKeys)
				)
				PlayerDataStoreServiceNetwork.packets.profileLoaded.sendTo({
					data = Squash.tobuffer(cursor),
					hiddenKeys = hiddenKeys,
				}, player)

				for _, keyName in self._attributeKeys:GetList() do
					AttributeUtils.setAttribute(player, keyName, (profile.Data :: any)[keyName])
				end
			end)
			:Catch(function(errorMessage: any): ...any
				if player.Parent == Players then
					ErrorReportingUtils.logFatal(
						"Player profile loading promise failed",
						ErrorReportingUtils.createFailureContext(errorMessage, {
							playerId = player.UserId,
							playerName = player.Name,
						})
					)
				end
				warn(
					`[PlayerDataStoreService] - Promise failed during profile loading for {player.UserId} ({errorMessage})`
				)
			end)
	end))
end

function PlayerDataStoreService.Destroy(self: PlayerDataStoreService): ()
	self._maid:Destroy()
end

return PlayerDataStoreService
