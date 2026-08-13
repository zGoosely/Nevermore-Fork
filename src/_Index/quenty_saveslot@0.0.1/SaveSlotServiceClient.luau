--!strict
--[=[
	Client-side save-slot metadata, selection, and lazy read-only active-slot API.
	Inactive slot contents remain server-only.

	@class SaveSlotServiceClient
]=]
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const PlayerDataStoreServiceClient = require("@game/ReplicatedStorage/Packages/PlayerDataStoreServiceClient")
const PlayerDataStoreServiceProfile = require("@game/ReplicatedStorage/Packages/PlayerDataStoreServiceProfile")
const PlayerDataStoreServiceUtils = require("@game/ReplicatedStorage/Packages/PlayerDataStoreServiceUtils")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const PromiseUtils = require("@game/ReplicatedStorage/Packages/PromiseUtils")
const Rx = require("@game/ReplicatedStorage/Packages/Rx")
const SaveSlotConstants = require("./Shared/SaveSlotConstants")
const SaveSlotNetwork = require("./Shared/SaveSlotNetwork")
const SaveSlotSerializationUtils = require("./Shared/SaveSlotSerializationUtils")
const SaveSlotTypes = require("./Shared/SaveSlotTypes")
const SaveSlotUtils = require("./Shared/SaveSlotUtils")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const Signal = require("@game/ReplicatedStorage/Packages/Signal")
const SlotsProfileData = require("@game/ReplicatedStorage/Packages/SlotsProfileData")
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

const SaveSlotServiceClient = {}
SaveSlotServiceClient.ServiceName = "SaveSlotServiceClient"

export type SaveSlotServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_playerDataStoreServiceClient: PlayerDataStoreServiceClient.PlayerDataStoreServiceClient,
		_slotStateChanged: Signal.Signal<>,
		_activeSlotDataChanged: Signal.Signal<>,
		_slotStatePromise: Promise.Promise<any>,
		_slotStateSequence: number,
		_activeSlotDataSequence: number,
		_activeSlotId: SaveSlotTypes.SlotId?,
		_lastActiveSlotId: SaveSlotTypes.SlotId?,
		_metadataMap: { [string]: SaveSlotTypes.SaveSlotMetadata },
		_replicatedSlotId: SaveSlotTypes.SlotId?,
		_activeSlotData: any,
		_hasActiveSlotData: boolean,
		_activeSlotObserverCount: number,
		_activeSlotSubscriptionRegistered: boolean,
		_activeSlotDataRequestQueued: boolean,
	},
	{} :: typeof({ __index = SaveSlotServiceClient })
))

local function invokeMutationAsync(query: any, request: any): Promise.Promise<any>
	return Promise.spawn(function(resolve, reject: (...any) -> ())
		const invoked, response = pcall(query.invoke, request)
		if not invoked then
			reject(response)
			return
		end
		if type(response) ~= "table" or response.success ~= true then
			reject(if type(response) == "table" then response.error else "Invalid server response")
			return
		end
		resolve(response.slotId)
	end)
end

function SaveSlotServiceClient.Init(self: SaveSlotServiceClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	PlayerDataStoreServiceProfile.Select(SlotsProfileData, "SlotsProfileData")
	self._playerDataStoreServiceClient = self._serviceBag:GetService(PlayerDataStoreServiceClient)
	self._slotStateChanged = self._maid:Add(Signal.new())
	self._activeSlotDataChanged = self._maid:Add(Signal.new())
	self._slotStatePromise = self._maid:GivePromise(Promise.new())
	self._slotStateSequence = -1
	self._activeSlotDataSequence = -1
	self._activeSlotId = nil
	self._lastActiveSlotId = nil
	self._metadataMap = {}
	self._replicatedSlotId = nil
	self._activeSlotData = nil
	self._hasActiveSlotData = false
	self._activeSlotObserverCount = 0
	self._activeSlotSubscriptionRegistered = false
	self._activeSlotDataRequestQueued = false

	SaveSlotNetwork.packets.slotStateChanged.listen(function(data: buffer)
		self:_applySlotStateBuffer(data)
	end)
	SaveSlotNetwork.packets.activeSlotInvalidated.listen(function(sequence: number)
		self:_handleActiveSlotInvalidation(sequence)
	end)
end

function SaveSlotServiceClient.Start(self: SaveSlotServiceClient)
	self._maid
		:GivePromise(self._playerDataStoreServiceClient:PromiseDataStore():Then(function()
			return self:_requestSlotStateAsync()
		end))
		:Catch(function(errorMessage)
			warn(`[SaveSlotServiceClient] - Failed to request slot state ({errorMessage})`)
		end)
end

--[=[
	Resolves when both the PlayerDataStoreService profile mirror and compact slot metadata are
	available. Active gameplay data remains lazy; request it with
	[SaveSlotServiceClient.GetActiveSlotDataAsync].

	@within SaveSlotServiceClient
	@return Promise
]=]
function SaveSlotServiceClient.ReadyAsync(self: SaveSlotServiceClient): Promise.Promise<any>
	return PromiseUtils.all({
		self._playerDataStoreServiceClient:PromiseDataStore(),
		self._slotStatePromise,
	})
end

--[=[
	Returns the cached active-slot gameplay data, or nil until it has been requested.
	The returned value is a deep copy.

	@within SaveSlotServiceClient
	@return any
]=]
function SaveSlotServiceClient.GetActiveSlotData(self: SaveSlotServiceClient): any
	if not self._activeSlotId or self._activeSlotId ~= self._replicatedSlotId or not self._hasActiveSlotData then
		return nil
	end
	return TableUtils.deepCopy(self._activeSlotData)
end

--[=[
	Requests and caches only the currently active slot's gameplay data. The payload
	is serialized with `SlotsProfileData.SlotDataSchema`; inactive slots are never sent.

	@within SaveSlotServiceClient
	@return Promise<any>
]=]
function SaveSlotServiceClient.GetActiveSlotDataAsync(self: SaveSlotServiceClient): Promise.Promise<any>
	return self:_requestActiveSlotDataAsync(false)
end

--[=[
	Reads a path from the cached active-slot data. Use [SaveSlotServiceClient.GetValueAsync]
	for a read that first requests a fresh snapshot.

	@within SaveSlotServiceClient
	@param path string
	@return any
]=]
function SaveSlotServiceClient.GetValue<T>(self: SaveSlotServiceClient, path: string): T?
	assert(SaveSlotUtils.isDataPath(path), "Bad path")
	return TableUtils.deepCopy(PlayerDataStoreServiceUtils.readValuePath(self:GetActiveSlotData(), path)) :: T?
end

--[=[
	Requests the active-slot snapshot and resolves with one value inside it.

	@within SaveSlotServiceClient
	@param path string
	@return Promise<any>
]=]
function SaveSlotServiceClient.GetValueAsync(self: SaveSlotServiceClient, path: string): Promise.Promise<any>
	assert(SaveSlotUtils.isDataPath(path), "Bad path")
	return self:GetActiveSlotDataAsync():Then(function(slotData)
		return TableUtils.deepCopy(PlayerDataStoreServiceUtils.readValuePath(slotData, path))
	end)
end

--[=[
	Observes the active slot's gameplay data. Subscribing lazily requests the active
	slot and enables compact invalidations; unsubscribing the last observer disables
	them on the server.

	@within SaveSlotServiceClient
	@return Observable
]=]
function SaveSlotServiceClient.ObserveActiveSlotData(self: SaveSlotServiceClient): Observable.Observable<any>
	return Observable.new(function(sub)
		const maid = Maid.new()
		self._activeSlotObserverCount += 1

		const function update()
			sub:Fire(self:GetActiveSlotData())
		end
		maid:Add(self._activeSlotDataChanged:Connect(update))
		maid:Add(self._slotStateChanged:Connect(update))
		update()

		if self._activeSlotObserverCount == 1 then
			maid:GivePromise(self:_requestActiveSlotDataAsync(true)):Catch(function(errorMessage)
				warn(`[SaveSlotServiceClient] - Failed to observe active slot data ({errorMessage})`)
			end)
		end

		maid:Add(function()
			self._activeSlotObserverCount -= 1
			if self._activeSlotObserverCount == 0 then
				if self._activeSlotSubscriptionRegistered then
					self._activeSlotSubscriptionRegistered = false
					SaveSlotNetwork.packets.activeSlotSubscriptionChanged.send(false)
				end
			end
		end)
		return maid
	end) :: any
end

--[=[
	Observes one path in the active slot. It follows slot selection changes and only
	keeps server invalidations enabled while subscribed.

	```lua
	SaveSlotServiceClient:ObserveAtKey("Coins"):Subscribe(function(coins)
		print(coins)
	end)
	```

	@within SaveSlotServiceClient
	@param path string
	@return Observable
]=]
function SaveSlotServiceClient.ObserveAtKey<T>(self: SaveSlotServiceClient, path: string): Observable.Observable<T?>
	assert(SaveSlotUtils.isDataPath(path), "Bad path")
	return self:ObserveActiveSlotData():Pipe({
		Rx.map(function(slotData)
			return TableUtils.deepCopy(PlayerDataStoreServiceUtils.readValuePath(slotData, path))
		end) :: any,
		Rx.distinct() :: any,
	}) :: any
end

--[=[
	Returns server-side slot selection configuration.

	@within SaveSlotServiceClient
	@return Promise<SaveSlotConfig>
]=]
function SaveSlotServiceClient.GetConfigAsync(_self: SaveSlotServiceClient): Promise.Promise<any>
	return Promise.spawn(function(resolve, reject: (...any) -> ())
		const success, response = pcall(SaveSlotNetwork.queries.getConfig.invoke, nil)
		if success and type(response) == "table" then
			resolve(response)
		else
			reject(response)
		end
	end)
end

--[=[
	Returns whether explicit slot selection is required.

	@within SaveSlotServiceClient
	@return Promise<boolean>
]=]
function SaveSlotServiceClient.GetExplicitSelectionRequiredAsync(self: SaveSlotServiceClient): Promise.Promise<any>
	return self:GetConfigAsync():Then(function(config: SaveSlotTypes.SaveSlotConfig)
		return config.explicitSelection
	end)
end

--[=[
	Returns the active slot ID, or nil when no slot is selected.

	@within SaveSlotServiceClient
	@return string?
]=]
function SaveSlotServiceClient.GetActiveSlotId(self: SaveSlotServiceClient): SaveSlotTypes.SlotId?
	return self._activeSlotId
end

--[=[
	Returns the last active slot ID.

	@within SaveSlotServiceClient
	@return string?
]=]
function SaveSlotServiceClient.GetLastActiveSlotId(self: SaveSlotServiceClient): SaveSlotTypes.SlotId?
	return self._lastActiveSlotId
end

--[=[
	Observes the active slot ID.

	@within SaveSlotServiceClient
	@return Observable
]=]
function SaveSlotServiceClient.ObserveActiveSlotId(
	self: SaveSlotServiceClient
): Observable.Observable<SaveSlotTypes.SlotId?>
	return Observable.new(function(sub)
		const connection = self._slotStateChanged:Connect(function()
			sub:Fire(self._activeSlotId)
		end)
		sub:Fire(self._activeSlotId)
		return connection
	end):Pipe({
		Rx.distinct() :: any,
	}) :: any
end

--[=[
	Returns sorted metadata for all local-player slots.

	@within SaveSlotServiceClient
	@return { SaveSlotMetadata }
]=]
function SaveSlotServiceClient.GetSlotList(self: SaveSlotServiceClient): { SaveSlotTypes.SaveSlotMetadata }
	return SaveSlotUtils.getSlotList(self._metadataMap)
end

--[=[
	Observes sorted slot metadata.

	@within SaveSlotServiceClient
	@return Observable
]=]
function SaveSlotServiceClient.ObserveSlotList(
	self: SaveSlotServiceClient
): Observable.Observable<{ SaveSlotTypes.SaveSlotMetadata }>
	return Observable.new(function(sub)
		const connection = self._slotStateChanged:Connect(function()
			sub:Fire(self:GetSlotList())
		end)
		sub:Fire(self:GetSlotList())
		return connection
	end) :: any
end

--[=[
	Returns metadata for one slot.

	@within SaveSlotServiceClient
	@param slotId string
	@return SaveSlotMetadata?
]=]
function SaveSlotServiceClient.GetSlotMetadata(
	self: SaveSlotServiceClient,
	slotId: SaveSlotTypes.SlotId
): SaveSlotTypes.SaveSlotMetadata?
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	return SaveSlotUtils.getSlotMetadata(self._metadataMap, slotId)
end

--[=[
	Observes metadata for one slot. Emits nil after deletion.

	@within SaveSlotServiceClient
	@param slotId string
	@return Observable
]=]
function SaveSlotServiceClient.ObserveSlotMetadata(
	self: SaveSlotServiceClient,
	slotId: SaveSlotTypes.SlotId
): Observable.Observable<SaveSlotTypes.SaveSlotMetadata?>
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	return self:ObserveSlotList():Pipe({
		Rx.map(function()
			return self:GetSlotMetadata(slotId)
		end) :: any,
		Rx.distinct() :: any,
	}) :: any
end

--[=[
	Returns the slot ID assigned to an index.

	@within SaveSlotServiceClient
	@param slotIndex number
	@return string?
]=]
function SaveSlotServiceClient.GetSlotIdFromIndex(self: SaveSlotServiceClient, slotIndex: number): SaveSlotTypes.SlotId?
	assert(type(slotIndex) == "number", "Bad slotIndex")
	return SaveSlotUtils.getSlotIdFromIndex(self._metadataMap, slotIndex)
end

--[=[
	Returns whether the local metadata mirror contains a slot.

	@within SaveSlotServiceClient
	@param slotId string
	@return boolean
]=]
function SaveSlotServiceClient.HasSlot(self: SaveSlotServiceClient, slotId: SaveSlotTypes.SlotId): boolean
	return self:GetSlotMetadata(slotId) ~= nil
end

--[=[
	Requests creation of a slot owned by the local player.

	@within SaveSlotServiceClient
	@param slotIndex number
	@param metadata SaveSlotMetadataInput?
	@return Promise<string>
]=]
function SaveSlotServiceClient.CreateSlotAsync(
	_self: SaveSlotServiceClient,
	slotIndex: number,
	metadata: SaveSlotTypes.SaveSlotMetadataInput?
): Promise.Promise<any>
	assert(
		type(slotIndex) == "number"
			and slotIndex % 1 == 0
			and slotIndex >= 1
			and slotIndex <= SaveSlotConstants.MAX_SLOT_COUNT,
		"Bad slotIndex"
	)
	assert(metadata == nil or type(metadata) == "table", "Bad metadata")
	return invokeMutationAsync(SaveSlotNetwork.queries.createSlot, {
		slotIndex = slotIndex,
		slotName = if metadata and metadata.SlotName then metadata.SlotName else "",
		summary = if metadata and metadata.Summary then metadata.Summary else "",
	})
end

--[=[
	Requests selection of a slot owned by the local player.

	@within SaveSlotServiceClient
	@param slotId string
	@return Promise<string>
]=]
function SaveSlotServiceClient.SelectSlotAsync(
	_self: SaveSlotServiceClient,
	slotId: SaveSlotTypes.SlotId
): Promise.Promise<any>
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	return invokeMutationAsync(SaveSlotNetwork.queries.selectSlot, slotId)
end

--[=[
	Requests deletion of an inactive slot owned by the local player.

	@within SaveSlotServiceClient
	@param slotId string
	@return Promise<string>
]=]
function SaveSlotServiceClient.DeleteSlotAsync(
	_self: SaveSlotServiceClient,
	slotId: SaveSlotTypes.SlotId
): Promise.Promise<any>
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	return invokeMutationAsync(SaveSlotNetwork.queries.deleteSlot, slotId)
end

--[=[
	Requests a name and/or summary change for one local-player slot.

	@within SaveSlotServiceClient
	@param slotId string
	@param metadata SaveSlotMetadataInput
	@return Promise<string>
]=]
function SaveSlotServiceClient.SetSlotMetadataAsync(
	_self: SaveSlotServiceClient,
	slotId: SaveSlotTypes.SlotId,
	metadata: SaveSlotTypes.SaveSlotMetadataInput
): Promise.Promise<any>
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	assert(type(metadata) == "table", "Bad metadata")
	return invokeMutationAsync(SaveSlotNetwork.queries.setMetadata, {
		slotId = slotId,
		hasSlotName = metadata.SlotName ~= nil,
		slotName = metadata.SlotName or "",
		hasSummary = metadata.Summary ~= nil,
		summary = metadata.Summary or "",
	})
end

function SaveSlotServiceClient._requestSlotStateAsync(self: SaveSlotServiceClient): Promise.Promise<any>
	return Promise.spawn(function(resolve, reject: (...any) -> ())
		const invoked, response = pcall(SaveSlotNetwork.queries.getSlotState.invoke, nil)
		if not invoked then
			reject(response)
			return
		end
		if typeof(response) ~= "buffer" or not self:_applySlotStateBuffer(response) then
			reject("Invalid slot-state response")
			return
		end
		resolve()
	end)
end

function SaveSlotServiceClient._requestActiveSlotDataAsync(
	self: SaveSlotServiceClient,
	subscribe: boolean
): Promise.Promise<any>
	return Promise.spawn(function(resolve, reject: (...any) -> ())
		const invoked, response = pcall(SaveSlotNetwork.queries.getActiveSlotData.invoke, subscribe)
		if not invoked then
			reject(response)
			return
		end
		if typeof(response) ~= "buffer" then
			reject("Invalid active-slot response")
			return
		end

		const decoded, snapshot = pcall(SaveSlotSerializationUtils.deserializeActiveSlotData, response)
		if not decoded then
			reject(snapshot)
			return
		end
		if snapshot.SlotId ~= self._activeSlotId or snapshot.Sequence < self._activeSlotDataSequence then
			if self._activeSlotObserverCount > 0 then
				self:_queueActiveSlotDataRequest()
			end
			resolve(self:GetActiveSlotData())
			return
		end

		self._activeSlotDataSequence = snapshot.Sequence
		self._replicatedSlotId = snapshot.SlotId
		self._activeSlotData = TableUtils.deepCopy(snapshot.Data)
		self._hasActiveSlotData = snapshot.SlotId ~= nil and snapshot.Data ~= nil
		self._activeSlotSubscriptionRegistered = self._activeSlotSubscriptionRegistered or subscribe
		self._activeSlotDataChanged:Fire()
		resolve(self:GetActiveSlotData())
	end)
end

function SaveSlotServiceClient._applySlotStateBuffer(self: SaveSlotServiceClient, data: buffer): boolean
	const decoded, slotState = pcall(SaveSlotSerializationUtils.deserializeSlotState, data)
	if not decoded then
		warn(`[SaveSlotServiceClient] - Failed to deserialize slot state ({slotState})`)
		return false
	end
	if slotState.Sequence <= self._slotStateSequence then
		return true
	end

	const activeSlotChanged = slotState.ActiveSlotId ~= self._activeSlotId
	self._slotStateSequence = slotState.Sequence
	self._activeSlotId = slotState.ActiveSlotId
	self._lastActiveSlotId = slotState.LastActiveSlotId
	self._metadataMap = slotState.Metadata
	if activeSlotChanged then
		self._activeSlotDataSequence = -1
		self._replicatedSlotId = nil
		self._activeSlotData = nil
		self._hasActiveSlotData = false
		self._activeSlotSubscriptionRegistered = false
		self._activeSlotDataChanged:Fire()
	end

	self._slotStateChanged:Fire()
	self._slotStatePromise:Resolve()
	if activeSlotChanged and self._activeSlotObserverCount > 0 then
		self:_queueActiveSlotDataRequest()
	end
	return true
end

function SaveSlotServiceClient._handleActiveSlotInvalidation(self: SaveSlotServiceClient, sequence: number)
	if sequence <= self._activeSlotDataSequence then
		return
	end

	self._activeSlotDataSequence = sequence
	self._activeSlotData = nil
	self._hasActiveSlotData = false
	self._activeSlotDataChanged:Fire()
	if self._activeSlotObserverCount > 0 then
		self:_queueActiveSlotDataRequest()
	end
end

function SaveSlotServiceClient._queueActiveSlotDataRequest(self: SaveSlotServiceClient)
	if self._activeSlotDataRequestQueued then
		return
	end

	self._activeSlotDataRequestQueued = true
	task.defer(function()
		if not self._maid then
			return
		end
		self._activeSlotDataRequestQueued = false
		if self._activeSlotObserverCount == 0 then
			return
		end

		self._maid:GivePromise(self:_requestActiveSlotDataAsync(true)):Catch(function(errorMessage)
			warn(`[SaveSlotServiceClient] - Failed to refresh active slot data ({errorMessage})`)
		end)
	end)
end

function SaveSlotServiceClient.Destroy(self: SaveSlotServiceClient)
	self._maid:DoCleaning()
	table.clear(self)
	setmetatable(self, nil)
end

return SaveSlotServiceClient
