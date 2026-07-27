--!nonstrict
--[=[
	Read-only local gift cache with map, per-gift, type-filtered, and Brio
	observation APIs.

	@class GiftingServiceClient
	@client
]=]

const require = require("../Loader").load()

const GameProductServiceClient = require("GameProductServiceClient")
const GiftingAssetTypes = require("GiftingAssetTypes")
const GiftingNetwork = require("GiftingNetwork")
const GiftingSerializationUtils = require("GiftingSerializationUtils")
const GiftingTypes = require("GiftingTypes")
const Maid = require("Maid")
const Observable = require("Observable")
const ObservableMap = require("ObservableMap")
const Promise = require("Promise")
const Rx = require("Rx")
const RxBrioUtils = require("RxBrioUtils")
const ServiceBag = require("ServiceBag")
const TableUtils = require("TableUtils")

type AssetType = GiftingTypes.GiftingAssetType
type GiftRecord = GiftingTypes.GiftRecord

const GiftingServiceClient = {}
GiftingServiceClient.ServiceName = "GiftingServiceClient"

export type GiftingServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_gameProductService: GameProductServiceClient.GameProductServiceClient,
		_giftMap: ObservableMap.ObservableMap<string, GiftRecord>,
		_readyPromise: Promise.Promise<()>,
		_sequence: number,
		_isReady: boolean,
	},
	{} :: typeof({ __index = GiftingServiceClient })
))

function GiftingServiceClient.Init(self: GiftingServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._gameProductService = self._serviceBag:GetService(GameProductServiceClient)
	self._giftMap = self._maid:Add(ObservableMap.new())
	self._readyPromise = self._maid:GivePromise(Promise.new())
	self._sequence = -1
	self._isReady = false
	self._maid:Add(self._gameProductService:RegisterOwnershipProvider(GiftingAssetTypes.GamePass, function(_, assetKey)
		return self:ReadyAsync():Then(function()
			return assetKey ~= nil and self:HasGift(assetKey)
		end)
	end, 1000))
	self._maid:Add(self._gameProductService:RegisterOwnershipProvider(GiftingAssetTypes.Product, function(_, assetKey)
		return self:ReadyAsync():Then(function()
			return assetKey ~= nil and self:HasGift(assetKey)
		end)
	end, 1000))

	GiftingNetwork.packets.giftsChanged.listen(function(data)
		self:_applySnapshot(data)
	end)
end

function GiftingServiceClient.Start(self: GiftingServiceClient): ()
	self._maid
		:GivePromise(Promise.spawn(function(resolve, reject)
			const succeeded, data = pcall(GiftingNetwork.queries.getGifts.invoke, nil)
			if not succeeded then
				reject(data)
				return
			end
			const applied, errorMessage = pcall(function()
				self:_applySnapshot(data)
			end)
			if not applied then
				reject(errorMessage)
				return
			end
			resolve()
		end))
		:Catch(function(errorMessage)
			warn(`[GiftingServiceClient] - Failed to load gifts: {errorMessage}`)
			if not self._isReady then
				self._readyPromise:Reject(errorMessage)
			end
		end)
end

--[=[
	Resolves after the first compact gift snapshot has been applied.

	@within GiftingServiceClient
	@return Promise
]=]
function GiftingServiceClient.ReadyAsync(self: GiftingServiceClient): Promise.Promise<()>
	return Promise.resolved(self._readyPromise)
end

--[=[
	Returns a deep copy of every local gift.

	@within GiftingServiceClient
	@return { [string]: GiftRecord }
]=]
function GiftingServiceClient.GetGifts(self: GiftingServiceClient): { [string]: GiftRecord }
	const gifts = {}
	for key, gift in self._giftMap :: any do
		gifts[key] = TableUtils.deepCopy(gift)
	end
	return gifts
end

--[=[
	Returns a copied gift record, if present.

	@within GiftingServiceClient
	@param assetKey string
	@return GiftRecord?
]=]
function GiftingServiceClient.GetGift(self: GiftingServiceClient, assetKey: string): GiftRecord?
	assert(type(assetKey) == "string" and assetKey ~= "", "Bad assetKey")
	return TableUtils.deepCopy(self._giftMap:Get(assetKey))
end

--[=[
	Returns whether the local player has a positive quantity of a gift.

	@within GiftingServiceClient
	@param assetKey string
	@return boolean
]=]
function GiftingServiceClient.HasGift(self: GiftingServiceClient, assetKey: string): boolean
	const gift = self:GetGift(assetKey)
	return gift ~= nil and gift.Quantity > 0
end

--[=[
	Checks persisted gifted ownership first and normal GameProductService ownership
	second.

	@within GiftingServiceClient
	@param assetKey string
	@param assetType GiftingAssetType
	@return Promise<boolean>
]=]
function GiftingServiceClient.HasEntitlementAsync(
	self: GiftingServiceClient,
	assetKey: string,
	assetType: AssetType
): Promise.Promise<boolean>
	assert(type(assetKey) == "string" and assetKey ~= "", "Bad assetKey")
	assert(GiftingAssetTypes:IsValue(assetType), "Bad assetType")
	return self:ReadyAsync():Then(function()
		return if self:HasGift(assetKey) then true else self._gameProductService:HasAssetAsync(assetType, assetKey)
	end)
end

--[=[
	Observes the complete gift map. Every emission is a deep copy.

	@within GiftingServiceClient
	@return Observable<{ [string]: GiftRecord }>
]=]
function GiftingServiceClient.ObserveGifts(self: GiftingServiceClient): Observable.Observable<{ [string]: GiftRecord }>
	return Observable.new(function(sub)
		const function update()
			sub:Fire(self:GetGifts())
		end
		const connection = self._giftMap.KeyValueChanged:Connect(update)
		update()
		return connection
	end)
end

--[=[
	Observes individual gift lifetimes as `(assetKey, giftRecord)` brios.

	@within GiftingServiceClient
	@return Observable<Brio<string, GiftRecord>>
]=]
function GiftingServiceClient.ObserveGiftsBrio(self: GiftingServiceClient): Observable.Observable<any>
	return self._giftMap:ObservePairsBrio():Pipe({
		RxBrioUtils.map(function(key, gift)
			return key, TableUtils.deepCopy(gift)
		end),
	}) :: any
end

--[=[
	Observes one copied gift record.

	@within GiftingServiceClient
	@param assetKey string
	@return Observable<GiftRecord?>
]=]
function GiftingServiceClient.ObserveGift(
	self: GiftingServiceClient,
	assetKey: string
): Observable.Observable<GiftRecord?>
	assert(type(assetKey) == "string" and assetKey ~= "", "Bad assetKey")
	return self._giftMap:ObserveAtKey(assetKey):Pipe({
		Rx.map(function(gift)
			return TableUtils.deepCopy(gift)
		end),
	}) :: any
end

--[=[
	Observes whether one gift is present.

	@within GiftingServiceClient
	@param assetKey string
	@return Observable<boolean>
]=]
function GiftingServiceClient.ObserveHasGift(
	self: GiftingServiceClient,
	assetKey: string
): Observable.Observable<boolean>
	return self:ObserveGift(assetKey):Pipe({
		Rx.map(function(gift)
			return gift ~= nil and gift.Quantity > 0
		end),
		Rx.distinct(),
	}) :: any
end

--[=[
	Observes a map containing only gifts of one type.

	@within GiftingServiceClient
	@param assetType GiftingAssetType
	@return Observable<{ [string]: GiftRecord }>
]=]
function GiftingServiceClient.ObserveGiftsType(
	self: GiftingServiceClient,
	assetType: AssetType
): Observable.Observable<{ [string]: GiftRecord }>
	assert(GiftingAssetTypes:IsValue(assetType), "Bad assetType")
	return self:ObserveGifts():Pipe({
		Rx.map(function(gifts)
			const filtered = {}
			for key, gift in gifts do
				if gift.AssetType == assetType then
					filtered[key] = gift
				end
			end
			return filtered
		end),
	}) :: any
end

--[=[
	Observes individual gift lifetimes for one type as `(assetKey, giftRecord)`
	brios.

	@within GiftingServiceClient
	@param assetType GiftingAssetType
	@return Observable<Brio<string, GiftRecord>>
]=]
function GiftingServiceClient.ObserveGiftsTypeBrio(
	self: GiftingServiceClient,
	assetType: AssetType
): Observable.Observable<any>
	assert(GiftingAssetTypes:IsValue(assetType), "Bad assetType")
	return self:ObserveGiftsBrio():Pipe({
		RxBrioUtils.map(function(key, gift)
			return gift, key
		end),
		RxBrioUtils.where(function(gift)
			return gift.AssetType == assetType
		end),
		RxBrioUtils.map(function(gift, key)
			return key, gift
		end),
	}) :: any
end

function GiftingServiceClient._applySnapshot(self: GiftingServiceClient, data: buffer): ()
	const sequence, gifts = GiftingSerializationUtils.deserialize(data)
	if sequence < self._sequence then
		return
	end
	self._sequence = sequence
	for key in self._giftMap :: any do
		if gifts[key] == nil then
			self._giftMap:Set(key, nil)
		end
	end
	for key, gift in gifts do
		if not TableUtils.deepEquivalent(self._giftMap:Get(key), gift) then
			self._giftMap:Set(key, gift)
		end
	end
	if not self._isReady then
		self._isReady = true
		self._readyPromise:Resolve()
	end
end

function GiftingServiceClient.Destroy(self: GiftingServiceClient): ()
	self._maid:Destroy()
end

return GiftingServiceClient
