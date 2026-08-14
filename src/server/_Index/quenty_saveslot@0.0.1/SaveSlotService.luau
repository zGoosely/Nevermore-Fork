--!strict
--[=[
	Provides player save slots on top of PlayerDataStoreService's single ProfileStore session.
	Account-wide data remains at the profile root; slot-scoped data is routed
	through `SaveSlots.Slots[slotId]` and never replicates to clients.

	@server
	@class SaveSlotService
]=]

const HttpService = game:GetService("HttpService")
const Players = game:GetService("Players")
const CmdrService = require("@game/ServerStorage/ServerPackages/CmdrService")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const PlayerDataStoreService = require("@game/ServerStorage/ServerPackages/PlayerDataStoreService")
const PlayerDataStoreServiceProfile = require("@game/ReplicatedStorage/Packages/PlayerDataStoreServiceProfile")
const PlayerDataStoreServiceUtils = require("@game/ReplicatedStorage/Packages/PlayerDataStoreServiceUtils")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const Rx = require("@game/ReplicatedStorage/Packages/Rx")
const RxPlayerUtils = require("@game/ReplicatedStorage/Packages/RxPlayerUtils")
const SaveSlotConstants = require("./Shared/SaveSlotConstants")
const SaveSlotNetwork = require("./Shared/SaveSlotNetwork")
const SaveSlotSerializationUtils = require("./Shared/SaveSlotSerializationUtils")
const SaveSlotTypes = require("./Shared/SaveSlotTypes")
const SaveSlotUtils = require("./Shared/SaveSlotUtils")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const SlotsProfileData = require("@game/ReplicatedStorage/Packages/SlotsProfileData")
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

const MAX_SLOT_NAME_LENGTH = 128
const MAX_SUMMARY_LENGTH = 512

type SummaryProvider = (player: Player, slotData: any) -> string?
type DefaultSlotDataProvider = (player: Player, slotIndex: number) -> any

const SaveSlotService = {}
SaveSlotService.ServiceName = "SaveSlotService"
SaveSlotService.ServerOnly = true

export type SaveSlotService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_playerDataStoreService: PlayerDataStoreService.PlayerDataStoreService,
		_cmdrService: CmdrService.CmdrService,
		_readyPromises: { [Player]: Promise.Promise<any> },
		_slotStateSequences: { [Player]: number },
		_activeSlotDataSequences: { [Player]: number },
		_replicatedActiveSlotIds: { [Player]: SaveSlotTypes.SlotId },
		_pendingSlotStateReplications: { [Player]: boolean },
		_explicitSelectionRequired: boolean,
		_maxSlotCount: number,
		_defaultSlotData: any,
		_defaultSlotDataProvider: DefaultSlotDataProvider?,
		_summaryProvider: SummaryProvider?,
		_started: boolean,
	},
	{} :: typeof({ __index = SaveSlotService })
))

local function toMutationResult(success: boolean, value: any): SaveSlotTypes.MutationResult
	if success then
		return {
			success = true,
			error = "",
			slotId = if type(value) == "string" then value else "",
		}
	end

	return {
		success = false,
		error = tostring(value),
		slotId = "",
	}
end

function SaveSlotService.Init(self: SaveSlotService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	PlayerDataStoreServiceProfile.Select(SlotsProfileData, "SlotsProfileData")
	self._playerDataStoreService = self._serviceBag:GetService(PlayerDataStoreService)
	self._cmdrService = self._serviceBag:GetService(CmdrService)
	self._readyPromises = setmetatable({}, { __mode = "k" }) :: any
	self._slotStateSequences = setmetatable({}, { __mode = "k" }) :: any
	self._activeSlotDataSequences = setmetatable({}, { __mode = "k" }) :: any
	self._replicatedActiveSlotIds = setmetatable({}, { __mode = "k" }) :: any
	self._pendingSlotStateReplications = setmetatable({}, { __mode = "k" }) :: any
	self._explicitSelectionRequired = false
	self._maxSlotCount = 1
	self._defaultSlotData = nil
	self._defaultSlotDataProvider = nil
	self._summaryProvider = nil
	self._started = false

	-- Inactive slot contents are server-only. The custom replicator replaces raw
	-- PlayerDataStoreService table references with schema-compressed slot state and lazy
	-- active-slot invalidations.
	self._playerDataStoreService:SetHiddenKey(SaveSlotConstants.ROOT_PATH)
	self._playerDataStoreService:AddReplicator(SaveSlotConstants.ROOT_PATH, function(player, _value, keyName)
		self:_replicateSlotValue(player, keyName)
	end)
end

function SaveSlotService.Start(self: SaveSlotService)
	self._started = true
	self._maid:Add(RxPlayerUtils.observePlayersBrio():Subscribe(function(brio)
		const maid, player = brio:ToMaidAndValue()
		maid:GivePromise(self:_getReadyPromise(player)):Catch(function(errorMessage)
			warn(`[SaveSlotService] - Failed to initialize {player.Name}: {errorMessage}`)
		end)
	end))
	self._maid:Add(Players.PlayerRemoving:Connect(function(player)
		self._readyPromises[player] = nil
		self._slotStateSequences[player] = nil
		self._activeSlotDataSequences[player] = nil
		self._replicatedActiveSlotIds[player] = nil
		self._pendingSlotStateReplications[player] = nil
	end))

	SaveSlotNetwork.queries.getConfig.listen(function(_, _player: Player?)
		return {
			explicitSelection = self._explicitSelectionRequired,
			maxSlotCount = self._maxSlotCount,
		}
	end)
	SaveSlotNetwork.queries.getSlotState.listen(function(_, player: Player?)
		if not player or not self._playerDataStoreService:GetProfile(player) then
			return SaveSlotSerializationUtils.serializeSlotState(0, {}, nil, nil)
		end

		return self:_getSlotStateBuffer(player)
	end)
	SaveSlotNetwork.queries.getActiveSlotData.listen(function(subscribe: boolean, player: Player?)
		if not player or not self._playerDataStoreService:GetProfile(player) then
			return SaveSlotSerializationUtils.serializeActiveSlotData(0, nil, nil)
		end

		const slotId = self:_getActiveSlotIdNow(player)
		const slotData = if slotId
			then self._playerDataStoreService:GetValue(player, SaveSlotUtils.getSlotPath(slotId))
			else nil
		if subscribe then
			self._replicatedActiveSlotIds[player] = slotId
		end
		return SaveSlotSerializationUtils.serializeActiveSlotData(
			self._activeSlotDataSequences[player] or 0,
			slotId,
			TableUtils.deepCopy(slotData)
		)
	end)
	SaveSlotNetwork.packets.activeSlotSubscriptionChanged.listen(function(isSubscribed: boolean, player: Player?)
		if not player then
			return
		end
		self._replicatedActiveSlotIds[player] = if isSubscribed then self:_getActiveSlotIdNow(player) else nil
	end)
	SaveSlotNetwork.queries.selectSlot.listen(function(slotId: string, player: Player?)
		if not player then
			return toMutationResult(false, "No player")
		end
		const success, result = self:SelectSlotAsync(player, slotId):Yield()
		return toMutationResult(success, result)
	end)
	SaveSlotNetwork.queries.createSlot.listen(function(request, player: Player?)
		if not player then
			return toMutationResult(false, "No player")
		end
		const success, result = self:CreateSlotAsync(player, request.slotIndex, {
			SlotName = if request.slotName ~= "" then request.slotName else nil,
			Summary = if request.summary ~= "" then request.summary else nil,
		}):Yield()
		return toMutationResult(success, result)
	end)
	SaveSlotNetwork.queries.deleteSlot.listen(function(slotId: string, player: Player?)
		if not player then
			return toMutationResult(false, "No player")
		end
		const success, result = self:DeleteSlotAsync(player, slotId):Yield()
		return toMutationResult(success, result)
	end)
	SaveSlotNetwork.queries.setMetadata.listen(function(request, player: Player?)
		if not player then
			return toMutationResult(false, "No player")
		end
		const success, result = self:SetSlotMetadataAsync(player, request.slotId, {
			SlotName = if request.hasSlotName then request.slotName else nil,
			Summary = if request.hasSummary then request.summary else nil,
		}):Yield()
		return toMutationResult(success, result)
	end)

	self._cmdrService:RegisterCommand({
		Name = "list-save-slots",
		Description = "Lists a player's save slots.",
		Group = "DefaultAdmin",
		Args = {
			{ Type = "player", Name = "player", Description = "The player whose slots should be listed." },
		},
		Run = function(_, player: Player)
			const ready, readyError = self:ReadyAsync(player):Yield()
			if not ready then
				return `Could not list {player.Name}'s save slots: {tostring(readyError)}.`
			end
			const activeSlotId = self:GetActiveSlotId(player)
			const lines = {}
			for _, metadata in self:GetSlotList(player) do
				table.insert(
					lines,
					`{metadata.SlotIndex}: {metadata.SlotName}{if metadata.SlotId == activeSlotId
						then " [active]"
						else ""} - {metadata.Summary}`
				)
			end
			return if #lines > 0 then table.concat(lines, "\n") else "No save slots."
		end,
	})
	self._cmdrService:RegisterCommand({
		Name = "set-save-slot",
		Description = "Selects one of a player's save slots by index.",
		Group = "DefaultAdmin",
		Args = {
			{ Type = "player", Name = "player", Description = "The player whose slot should change." },
			{ Type = "integer", Name = "slotIndex", Description = "The slot index to select." },
		},
		Run = function(_, player: Player, slotIndex: number)
			const ready, readyError = self:ReadyAsync(player):Yield()
			if not ready then
				return `Could not select slot {slotIndex} for {player.Name}: {tostring(readyError)}.`
			end
			const slotId = self:GetSlotIdFromIndex(player, slotIndex)
			if not slotId then
				return `Could not select slot {slotIndex} for {player.Name}: the slot does not exist.`
			end
			const selected, selectError = self:SelectSlotAsync(player, slotId):Yield()
			if not selected then
				return `Could not select slot {slotIndex} for {player.Name}: {tostring(selectError)}.`
			end
			return `Selected slot {slotIndex} for {player.Name}.`
		end,
	})
	self._cmdrService:RegisterCommand({
		Name = "create-save-slot",
		Description = "Creates a player's save slot at an unused index.",
		Group = "DefaultAdmin",
		Args = {
			{ Type = "player", Name = "player", Description = "The player who owns the slot." },
			{ Type = "integer", Name = "slotIndex", Description = "The slot index to create." },
		},
		Run = function(_, player: Player, slotIndex: number)
			const created, slotIdOrError = self:CreateSlotAsync(player, slotIndex):Yield()
			if not created then
				return `Could not create slot {slotIndex} for {player.Name}: {tostring(slotIdOrError)}.`
			end
			return `Created slot {slotIndex} ({slotIdOrError}) for {player.Name}.`
		end,
	})
	self._cmdrService:RegisterCommand({
		Name = "delete-save-slot",
		Description = "Deletes one of a player's inactive save slots.",
		Group = "DefaultAdmin",
		Args = {
			{ Type = "player", Name = "player", Description = "The player who owns the slot." },
			{ Type = "integer", Name = "slotIndex", Description = "The slot index to delete." },
		},
		Run = function(_, player: Player, slotIndex: number)
			const ready, readyError = self:ReadyAsync(player):Yield()
			if not ready then
				return `Could not delete slot {slotIndex} for {player.Name}: {tostring(readyError)}.`
			end
			const slotId = self:GetSlotIdFromIndex(player, slotIndex)
			if not slotId then
				return `Could not delete slot {slotIndex} for {player.Name}: the slot does not exist.`
			end
			const deleted, deleteError = self:DeleteSlotAsync(player, slotId):Yield()
			if not deleted then
				return `Could not delete slot {slotIndex} for {player.Name}: {tostring(deleteError)}.`
			end
			return `Deleted slot {slotIndex} for {player.Name}.`
		end,
	})
end

--[=[
	Requires players to explicitly select a slot instead of automatically loading
	their last active slot. Call before ServiceBag:Start().

	@within SaveSlotService
]=]
function SaveSlotService.RequireExplicitSelection(self: SaveSlotService)
	assert(not self._started, "RequireExplicitSelection must be called before Start")
	self._explicitSelectionRequired = true
end

--[=[
	Returns whether automatic slot selection is disabled.

	@within SaveSlotService
	@return boolean
]=]
function SaveSlotService.GetExplicitSelectionRequired(self: SaveSlotService): boolean
	return self._explicitSelectionRequired
end

--[=[
	Sets the maximum number of indexed slots. Call before ServiceBag:Start().

	@within SaveSlotService
	@param maxSlotCount number
]=]
function SaveSlotService.SetMaxSlotCount(self: SaveSlotService, maxSlotCount: number)
	assert(not self._started, "SetMaxSlotCount must be called before Start")
	assert(
		type(maxSlotCount) == "number"
			and maxSlotCount % 1 == 0
			and maxSlotCount >= 1
			and maxSlotCount <= SaveSlotConstants.MAX_SLOT_COUNT,
		"Bad maxSlotCount"
	)
	self._maxSlotCount = maxSlotCount
end

--[=[
	Sets the table copied into every newly created slot.

	@within SaveSlotService
	@param defaultSlotData any
]=]
function SaveSlotService.SetDefaultSlotData(self: SaveSlotService, defaultSlotData: any)
	assert(not self._started, "SetDefaultSlotData must be called before Start")
	assert(defaultSlotData ~= nil and type(defaultSlotData) ~= "function", "Bad defaultSlotData")
	self._defaultSlotData = TableUtils.deepCopy(defaultSlotData)
	self._defaultSlotDataProvider = nil
end

--[=[
	Sets a callback that builds the initial data for each new slot.

	@within SaveSlotService
	@param provider (Player, number) -> any
]=]
function SaveSlotService.SetDefaultSlotDataProvider(self: SaveSlotService, provider: DefaultSlotDataProvider)
	assert(not self._started, "SetDefaultSlotDataProvider must be called before Start")
	assert(type(provider) == "function", "Bad provider")
	self._defaultSlotData = nil
	self._defaultSlotDataProvider = provider
end

--[=[
	Sets a server callback used to refresh slot summaries after selection and
	SaveSlotService-routed data writes.

	@within SaveSlotService
	@param provider (Player, any) -> string?
]=]
function SaveSlotService.SetDefaultSummaryProvider(self: SaveSlotService, provider: SummaryProvider)
	assert(type(provider) == "function", "Bad provider")
	self._summaryProvider = provider
end

--[=[
	Resolves after PlayerDataStoreService has loaded and SaveSlotService has initialized the
	player's slot state.

	@within SaveSlotService
	@param player Player
	@return Promise
]=]
function SaveSlotService.ReadyAsync(self: SaveSlotService, player: Player): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:_getReadyPromise(player)
end

--[=[
	Returns the active slot ID, or nil while no slot is selected.

	@within SaveSlotService
	@param player Player
	@return string?
]=]
function SaveSlotService.GetActiveSlotId(self: SaveSlotService, player: Player): SaveSlotTypes.SlotId?
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:_getActiveSlotIdNow(player)
end

--[=[
	Returns the last slot selected in this or a previous session.

	@within SaveSlotService
	@param player Player
	@return string?
]=]
function SaveSlotService.GetLastActiveSlotId(self: SaveSlotService, player: Player): SaveSlotTypes.SlotId?
	assert(t.instanceIsA("Player")(player), "Bad player")
	return SaveSlotUtils.toOptionalSlotId(
		self._playerDataStoreService:GetValue(player, SaveSlotConstants.LAST_ACTIVE_SLOT_ID_PATH)
	)
end

--[=[
	Observes the active slot ID.

	@within SaveSlotService
	@param player Player
	@return Observable
]=]
function SaveSlotService.ObserveActiveSlotId(
	self: SaveSlotService,
	player: Player
): Observable.Observable<SaveSlotTypes.SlotId?>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self._playerDataStoreService:ObserveAtKey(player, SaveSlotConstants.ACTIVE_SLOT_ID_PATH):Pipe({
		Rx.map(SaveSlotUtils.toOptionalSlotId) :: any,
	}) :: any
end

--[=[
	Returns sorted metadata for all of a player's slots.

	@within SaveSlotService
	@param player Player
	@return { SaveSlotMetadata }
]=]
function SaveSlotService.GetSlotList(self: SaveSlotService, player: Player): { SaveSlotTypes.SaveSlotMetadata }
	assert(t.instanceIsA("Player")(player), "Bad player")
	return SaveSlotUtils.getSlotList(self:_getMetadataMap(player))
end

--[=[
	Observes sorted metadata for all slots.

	@within SaveSlotService
	@param player Player
	@return Observable
]=]
function SaveSlotService.ObserveSlotList(
	self: SaveSlotService,
	player: Player
): Observable.Observable<{ SaveSlotTypes.SaveSlotMetadata }>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self._playerDataStoreService:ObserveAtKey(player, SaveSlotConstants.METADATA_PATH):Pipe({
		Rx.map(SaveSlotUtils.getSlotList) :: any,
	}) :: any
end

--[=[
	Returns metadata for one slot.

	@within SaveSlotService
	@param player Player
	@param slotId string
	@return SaveSlotMetadata?
]=]
function SaveSlotService.GetSlotMetadata(
	self: SaveSlotService,
	player: Player,
	slotId: SaveSlotTypes.SlotId
): SaveSlotTypes.SaveSlotMetadata?
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	return SaveSlotUtils.getSlotMetadata(self:_getMetadataMap(player), slotId)
end

--[=[
	Observes metadata for one slot. Emits nil after the slot is deleted.

	@within SaveSlotService
	@param player Player
	@param slotId string
	@return Observable
]=]
function SaveSlotService.ObserveSlotMetadata(
	self: SaveSlotService,
	player: Player,
	slotId: SaveSlotTypes.SlotId
): Observable.Observable<SaveSlotTypes.SaveSlotMetadata?>
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	return self._playerDataStoreService:ObserveAtKey(player, SaveSlotConstants.METADATA_PATH):Pipe({
		Rx.map(function(metadataMap)
			return SaveSlotUtils.getSlotMetadata(metadataMap, slotId)
		end) :: any,
	}) :: any
end

--[=[
	Returns the slot ID assigned to an index.

	@within SaveSlotService
	@param player Player
	@param slotIndex number
	@return string?
]=]
function SaveSlotService.GetSlotIdFromIndex(
	self: SaveSlotService,
	player: Player,
	slotIndex: number
): SaveSlotTypes.SlotId?
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(type(slotIndex) == "number", "Bad slotIndex")
	return SaveSlotUtils.getSlotIdFromIndex(self:_getMetadataMap(player), slotIndex)
end

--[=[
	Returns whether a slot exists and has a data table.

	@within SaveSlotService
	@param player Player
	@param slotId string
	@return boolean
]=]
function SaveSlotService.HasSlot(self: SaveSlotService, player: Player, slotId: SaveSlotTypes.SlotId): boolean
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	return self:_getMetadataMap(player)[slotId] ~= nil and self:_getSlotsMap(player)[slotId] ~= nil
end

--[=[
	Creates a new slot at an unused index.

	@within SaveSlotService
	@param player Player
	@param slotIndex number
	@param metadata SaveSlotMetadataInput?
	@return Promise<string>
]=]
function SaveSlotService.CreateSlotAsync(
	self: SaveSlotService,
	player: Player,
	slotIndex: number,
	metadata: SaveSlotTypes.SaveSlotMetadataInput?
): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:_getReadyPromise(player):Then(function()
		return self:_createSlotNow(player, slotIndex, metadata)
	end)
end

--[=[
	Selects an existing slot.

	@within SaveSlotService
	@param player Player
	@param slotId string
	@return Promise
]=]
function SaveSlotService.SelectSlotAsync(
	self: SaveSlotService,
	player: Player,
	slotId: SaveSlotTypes.SlotId
): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:_getReadyPromise(player):Then(function()
		self:_selectSlotNow(player, slotId)
		return slotId
	end)
end

--[=[
	Deletes an inactive slot and all data stored inside it.

	@within SaveSlotService
	@param player Player
	@param slotId string
	@return Promise
]=]
function SaveSlotService.DeleteSlotAsync(
	self: SaveSlotService,
	player: Player,
	slotId: SaveSlotTypes.SlotId
): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:_getReadyPromise(player):Then(function()
		assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
		assert(slotId ~= self:_getActiveSlotIdNow(player), "Cannot delete the active slot")
		assert(self:HasSlot(player, slotId), `Slot {slotId} does not exist`)

		-- PlayerDataStoreService deliberately rejects nil SetValue arguments. Rewrite the
		-- hidden map so removing the slot remains one valid PlayerDataStoreService write.
		const slotsMap = TableUtils.deepCopy(self:_getSlotsMap(player))
		slotsMap[slotId] = nil
		self._playerDataStoreService:SetValue(player, SaveSlotConstants.SLOTS_PATH, slotsMap)
		const metadataMap = TableUtils.deepCopy(self:_getMetadataMap(player))
		metadataMap[slotId] = nil
		self._playerDataStoreService:SetValue(player, SaveSlotConstants.METADATA_PATH, metadataMap)
		if self._playerDataStoreService:GetValue(player, SaveSlotConstants.LAST_ACTIVE_SLOT_ID_PATH) == slotId then
			self._playerDataStoreService:SetValue(player, SaveSlotConstants.LAST_ACTIVE_SLOT_ID_PATH, "")
		end
		return slotId
	end)
end

--[=[
	Changes a slot's mutable name and/or summary.

	@within SaveSlotService
	@param player Player
	@param slotId string
	@param metadata SaveSlotMetadataInput
	@return Promise
]=]
function SaveSlotService.SetSlotMetadataAsync(
	self: SaveSlotService,
	player: Player,
	slotId: SaveSlotTypes.SlotId,
	metadata: SaveSlotTypes.SaveSlotMetadataInput
): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(type(metadata) == "table", "Bad metadata")
	return self:_getReadyPromise(player):Then(function()
		const metadataMap = TableUtils.deepCopy(self:_getMetadataMap(player))
		const current = metadataMap[slotId]
		assert(current ~= nil, `Slot {slotId} does not exist`)
		if metadata.SlotName ~= nil then
			assert(type(metadata.SlotName) == "string" and #metadata.SlotName <= MAX_SLOT_NAME_LENGTH, "Bad SlotName")
			current.SlotName = metadata.SlotName
		end
		if metadata.Summary ~= nil then
			assert(type(metadata.Summary) == "string" and #metadata.Summary <= MAX_SUMMARY_LENGTH, "Bad Summary")
			current.Summary = metadata.Summary
		end
		self._playerDataStoreService:SetValue(player, SaveSlotConstants.METADATA_PATH, metadataMap)
		return slotId
	end)
end

--[=[
	Returns a deep copy of the active slot's full data table.

	@within SaveSlotService
	@param player Player
	@return any
]=]
function SaveSlotService.GetActiveSlotData(self: SaveSlotService, player: Player): any
	assert(t.instanceIsA("Player")(player), "Bad player")
	const slotId = assert(self:_getActiveSlotIdNow(player), "Player has no active save slot")
	return TableUtils.deepCopy(self._playerDataStoreService:GetValue(player, SaveSlotUtils.getSlotPath(slotId)))
end

--[=[
	Observes the full active slot data, switching automatically when the active
	slot changes.

	@within SaveSlotService
	@param player Player
	@return Observable
]=]
function SaveSlotService.ObserveActiveSlotData(self: SaveSlotService, player: Player): Observable.Observable<any>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:ObserveActiveSlotId(player):Pipe({
		Rx.switchMap(function(slotId: SaveSlotTypes.SlotId?)
			if not slotId then
				return Rx.of(nil)
			end
			return self._playerDataStoreService:ObserveAtKey(player, SaveSlotUtils.getSlotPath(slotId))
		end) :: any,
	}) :: any
end

--[=[
	Reads a dot-separated path from the active slot.

	@within SaveSlotService
	@param player Player
	@param path string
	@return any
]=]
function SaveSlotService.GetValue<T>(self: SaveSlotService, player: Player, path: string): T?
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(SaveSlotUtils.isDataPath(path), "Bad path")
	const slotId = assert(self:_getActiveSlotIdNow(player), "Player has no active save slot")
	return TableUtils.deepCopy(
			self._playerDataStoreService:GetValue(player, SaveSlotUtils.getSlotPath(slotId, path))
		) :: T?
end

--[=[
	Writes a value or updater callback to a dot-separated path in the active slot.

	@within SaveSlotService
	@param player Player
	@param path string
	@param value any
	@return any
]=]
function SaveSlotService.SetValue(self: SaveSlotService, player: Player, path: string, value: any): any
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(SaveSlotUtils.isDataPath(path), "Bad path")
	const slotId = assert(self:_getActiveSlotIdNow(player), "Player has no active save slot")
	const result = self._playerDataStoreService:SetValue(player, SaveSlotUtils.getSlotPath(slotId, path), value)
	self:_refreshSummary(player, slotId)
	return result
end

--[=[
	Updates the active slot's entire data table from a callback.

	@within SaveSlotService
	@param player Player
	@param callback (any) -> any
	@return any
]=]
function SaveSlotService.UpdateActiveSlot(self: SaveSlotService, player: Player, callback: (any) -> any): any
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(type(callback) == "function", "Bad callback")
	const slotId = assert(self:_getActiveSlotIdNow(player), "Player has no active save slot")
	const result = self._playerDataStoreService:SetValue(player, SaveSlotUtils.getSlotPath(slotId), callback)
	self:_refreshSummary(player, slotId)
	return result
end

--[=[
	Observes a dot-separated path in the active slot and follows slot changes.

	@within SaveSlotService
	@param player Player
	@param path string
	@return Observable
]=]
function SaveSlotService.ObserveAtKey<T>(self: SaveSlotService, player: Player, path: string): Observable.Observable<T?>
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(SaveSlotUtils.isDataPath(path), "Bad path")
	return self:ObserveActiveSlotId(player):Pipe({
		Rx.switchMap(function(slotId: SaveSlotTypes.SlotId?)
			if not slotId then
				return Rx.of(nil)
			end
			return self._playerDataStoreService:ObserveAtKey(player, SaveSlotUtils.getSlotPath(slotId, path))
		end) :: any,
	}) :: any
end

function SaveSlotService._getSlotStateBuffer(self: SaveSlotService, player: Player): buffer
	return SaveSlotSerializationUtils.serializeSlotState(
		self._slotStateSequences[player] or 0,
		self:_getMetadataMap(player),
		self:_getActiveSlotIdNow(player),
		SaveSlotUtils.toOptionalSlotId(
			self._playerDataStoreService:GetValue(player, SaveSlotConstants.LAST_ACTIVE_SLOT_ID_PATH)
		)
	)
end

function SaveSlotService._queueSlotStateReplication(self: SaveSlotService, player: Player)
	self._slotStateSequences[player] = (self._slotStateSequences[player] or 0) + 1
	if self._pendingSlotStateReplications[player] then
		return
	end

	self._pendingSlotStateReplications[player] = true
	task.defer(function()
		if not self._maid or not self._pendingSlotStateReplications[player] then
			return
		end
		self._pendingSlotStateReplications[player] = nil
		if player.Parent ~= Players or not self._playerDataStoreService:GetProfile(player) then
			return
		end

		SaveSlotNetwork.packets.slotStateChanged.sendTo(self:_getSlotStateBuffer(player), player)
	end)
end

function SaveSlotService._invalidateActiveSlotData(self: SaveSlotService, player: Player)
	const sequence = (self._activeSlotDataSequences[player] or 0) + 1
	self._activeSlotDataSequences[player] = sequence
	const activeSlotId = self:_getActiveSlotIdNow(player)
	if activeSlotId and self._replicatedActiveSlotIds[player] == activeSlotId then
		SaveSlotNetwork.packets.activeSlotInvalidated.sendTo(sequence, player)
	end
end

function SaveSlotService._replicateSlotValue(self: SaveSlotService, player: Player, keyName: string)
	if keyName == SaveSlotConstants.ROOT_PATH then
		self._replicatedActiveSlotIds[player] = nil
		self:_queueSlotStateReplication(player)
		self:_invalidateActiveSlotData(player)
		return
	end
	if keyName == SaveSlotConstants.ACTIVE_SLOT_ID_PATH then
		self._replicatedActiveSlotIds[player] = nil
		self:_queueSlotStateReplication(player)
		self:_invalidateActiveSlotData(player)
		return
	end

	if keyName == SaveSlotConstants.SLOTS_PATH then
		self:_invalidateActiveSlotData(player)
		return
	end

	const slotsPrefix = SaveSlotConstants.SLOTS_PATH .. "."
	if string.sub(keyName, 1, #slotsPrefix) == slotsPrefix then
		const slotId = PlayerDataStoreServiceUtils.splitValuePath(string.sub(keyName, #slotsPrefix + 1))
		if slotId == self:_getActiveSlotIdNow(player) then
			self:_invalidateActiveSlotData(player)
		end
		return
	end

	self:_queueSlotStateReplication(player)
end

function SaveSlotService._getMetadataMap(
	self: SaveSlotService,
	player: Player
): { [string]: SaveSlotTypes.SaveSlotMetadata }
	const value = self._playerDataStoreService:GetValue(player, SaveSlotConstants.METADATA_PATH)
	return if type(value) == "table" then value :: any else {}
end

function SaveSlotService._getSlotsMap(self: SaveSlotService, player: Player): { [string]: any }
	const value = self._playerDataStoreService:GetValue(player, SaveSlotConstants.SLOTS_PATH)
	return if type(value) == "table" then value :: any else {}
end

function SaveSlotService._getActiveSlotIdNow(self: SaveSlotService, player: Player): SaveSlotTypes.SlotId?
	return SaveSlotUtils.toOptionalSlotId(
		self._playerDataStoreService:GetValue(player, SaveSlotConstants.ACTIVE_SLOT_ID_PATH)
	)
end

function SaveSlotService._getDefaultSlotData(self: SaveSlotService, player: Player, slotIndex: number): any
	const provider = self._defaultSlotDataProvider
	if provider then
		const success, value = pcall(provider, player, slotIndex)
		if not success then
			error(`Default slot data provider failed: {value}`)
		end
		assert(value ~= nil, "Default slot data provider returned nil")
		return TableUtils.deepCopy(value)
	end

	assert(
		self._defaultSlotData ~= nil,
		"Configure new slot data with SetDefaultSlotData or SetDefaultSlotDataProvider before Start"
	)
	return TableUtils.deepCopy(self._defaultSlotData)
end

function SaveSlotService._refreshSummary(self: SaveSlotService, player: Player, slotId: SaveSlotTypes.SlotId)
	const provider = self._summaryProvider
	if not provider then
		return
	end

	const slotData = self._playerDataStoreService:GetValue(player, SaveSlotUtils.getSlotPath(slotId))
	const success, summary = pcall(provider, player, TableUtils.deepCopy(slotData))
	if not success then
		warn(`[SaveSlotService] - Summary provider failed for {player.Name}: {summary}`)
		return
	end
	if summary ~= nil and type(summary) ~= "string" then
		warn(`[SaveSlotService] - Summary provider returned {typeof(summary)} instead of a string`)
		return
	end

	const metadataMap = TableUtils.deepCopy(self:_getMetadataMap(player))
	const metadata = metadataMap[slotId]
	if not metadata then
		return
	end

	const resolvedSummary = summary or ""
	if metadata.Summary == resolvedSummary then
		return
	end
	metadata.Summary = string.sub(resolvedSummary, 1, MAX_SUMMARY_LENGTH)
	self._playerDataStoreService:SetValue(player, SaveSlotConstants.METADATA_PATH, metadataMap)
end

function SaveSlotService._createSlotNow(
	self: SaveSlotService,
	player: Player,
	slotIndex: number,
	metadataInput: SaveSlotTypes.SaveSlotMetadataInput?
): SaveSlotTypes.SlotId
	assert(
		type(slotIndex) == "number" and slotIndex % 1 == 0 and slotIndex >= 1 and slotIndex <= self._maxSlotCount,
		`slotIndex must be an integer in range [1, {self._maxSlotCount}]`
	)
	assert(metadataInput == nil or type(metadataInput) == "table", "Bad metadata")

	const metadataMap = TableUtils.deepCopy(self:_getMetadataMap(player))
	assert(SaveSlotUtils.getSlotIdFromIndex(metadataMap, slotIndex) == nil, `Slot {slotIndex} already exists`)

	const slotId = HttpService:GenerateGUID(false)
	const slotName = if metadataInput and metadataInput.SlotName ~= nil
		then metadataInput.SlotName
		else `Slot {slotIndex}`
	const summary = if metadataInput and metadataInput.Summary ~= nil then metadataInput.Summary else ""
	assert(type(slotName) == "string" and #slotName <= MAX_SLOT_NAME_LENGTH, "Bad metadata.SlotName")
	assert(type(summary) == "string" and #summary <= MAX_SUMMARY_LENGTH, "Bad metadata.Summary")

	const now = os.time()
	const metadata: SaveSlotTypes.SaveSlotMetadata = {
		SlotId = slotId,
		SlotIndex = slotIndex,
		SlotName = slotName,
		CreatedTime = now,
		LastPlayedTime = 0,
		Summary = summary,
	}

	self._playerDataStoreService:SetValue(
		player,
		SaveSlotUtils.getSlotPath(slotId),
		self:_getDefaultSlotData(player, slotIndex)
	)
	metadataMap[slotId] = metadata
	self._playerDataStoreService:SetValue(player, SaveSlotConstants.METADATA_PATH, metadataMap)
	self:_refreshSummary(player, slotId)
	return slotId
end

function SaveSlotService._selectSlotNow(self: SaveSlotService, player: Player, slotId: SaveSlotTypes.SlotId)
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	const metadataMap = TableUtils.deepCopy(self:_getMetadataMap(player))
	const metadata = metadataMap[slotId]
	assert(metadata ~= nil, `Slot {slotId} does not exist`)
	assert(self:_getSlotsMap(player)[slotId] ~= nil, `Slot {slotId} has no data`)

	metadata.LastPlayedTime = os.time()
	self._playerDataStoreService:SetValue(player, SaveSlotConstants.METADATA_PATH, metadataMap)
	self._playerDataStoreService:SetValue(player, SaveSlotConstants.ACTIVE_SLOT_ID_PATH, slotId)
	self._playerDataStoreService:SetValue(player, SaveSlotConstants.LAST_ACTIVE_SLOT_ID_PATH, slotId)
	self:_refreshSummary(player, slotId)
end

function SaveSlotService._initializePlayerAsync(self: SaveSlotService, player: Player): Promise.Promise<any>
	return self._playerDataStoreService:PromiseProfile(player):Then(function()
		if type(self._playerDataStoreService:GetValue(player, SaveSlotConstants.METADATA_PATH)) ~= "table" then
			self._playerDataStoreService:SetValue(player, SaveSlotConstants.METADATA_PATH, {})
		end
		if type(self._playerDataStoreService:GetValue(player, SaveSlotConstants.SLOTS_PATH)) ~= "table" then
			self._playerDataStoreService:SetValue(player, SaveSlotConstants.SLOTS_PATH, {})
		end
		if
			type(self._playerDataStoreService:GetValue(player, SaveSlotConstants.LAST_ACTIVE_SLOT_ID_PATH)) ~= "string"
		then
			self._playerDataStoreService:SetValue(player, SaveSlotConstants.LAST_ACTIVE_SLOT_ID_PATH, "")
		end

		-- ActiveSlotId is session state. LastActiveSlotId is the persisted choice.
		self._playerDataStoreService:SetValue(player, SaveSlotConstants.ACTIVE_SLOT_ID_PATH, "")

		const metadataMap = self:_getMetadataMap(player)
		const slotsMap = self:_getSlotsMap(player)
		const joinData = player:GetJoinData()
		const teleportData = joinData and joinData.TeleportData
		const incomingSlotId = teleportData and teleportData[SaveSlotConstants.TELEPORT_DATA_SLOT_KEY]
		if
			SaveSlotUtils.isSlotId(incomingSlotId)
			and metadataMap[incomingSlotId]
			and slotsMap[incomingSlotId] ~= nil
		then
			self:_selectSlotNow(player, incomingSlotId)
			return
		end

		if self._explicitSelectionRequired then
			return
		end

		const lastActiveSlotId = SaveSlotUtils.toOptionalSlotId(
			self._playerDataStoreService:GetValue(player, SaveSlotConstants.LAST_ACTIVE_SLOT_ID_PATH)
		)
		if lastActiveSlotId and metadataMap[lastActiveSlotId] and slotsMap[lastActiveSlotId] ~= nil then
			self:_selectSlotNow(player, lastActiveSlotId)
			return
		end

		local defaultSlotId = SaveSlotUtils.getSlotIdFromIndex(metadataMap, SaveSlotConstants.DEFAULT_SLOT_INDEX)
		if not defaultSlotId then
			defaultSlotId = self:_createSlotNow(player, SaveSlotConstants.DEFAULT_SLOT_INDEX, nil)
		end
		self:_selectSlotNow(player, defaultSlotId)
	end)
end

function SaveSlotService._getReadyPromise(self: SaveSlotService, player: Player): Promise.Promise<any>
	local promise = self._readyPromises[player]
	if promise then
		return promise
	end

	promise = self._maid:GivePromise(self:_initializePlayerAsync(player))
	self._readyPromises[player] = promise
	return promise
end

function SaveSlotService.Destroy(self: SaveSlotService)
	self._maid:DoCleaning()
	table.clear(self)
	setmetatable(self, nil)
end

return SaveSlotService
