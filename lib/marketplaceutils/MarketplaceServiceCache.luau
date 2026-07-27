--!strict
--[=[
	Caches MarketplaceService product-information promises for the lifetime of the
	server or client. Concurrent callers share one request, successful responses
	remain cached, and failed requests are removed so a later call can retry.

	@class MarketplaceServiceCache
]=]

const require = require("../Loader").load()

const Maid = require("Maid")
const MarketplaceUtils = require("MarketplaceUtils")
const Promise = require("Promise")
const ServiceBag = require("ServiceBag")

const DEFAULT_MAX_SIZE = 2048

type ProductInfo = MarketplaceUtils.AssetProductInfo | MarketplaceUtils.GamePassOrDeveloperProductInfo
type CacheEntry = {
	promise: Promise.Promise<any>,
	lastAccess: number,
}

const MarketplaceServiceCache = {}
MarketplaceServiceCache.ServiceName = "MarketplaceServiceCache"

export type MarketplaceServiceCache = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_cache: { [string]: CacheEntry },
		_accessCounter: number,
		_maxSize: number,
	},
	{} :: typeof({ __index = MarketplaceServiceCache })
))

function MarketplaceServiceCache.Init(self: MarketplaceServiceCache, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._cache = {}
	self._accessCounter = 0
	self._maxSize = DEFAULT_MAX_SIZE
end

--[=[
	Sets the maximum number of successful product-information requests retained in
	the cache. The least recently used entries are removed when the limit shrinks.

	@within MarketplaceServiceCache
	@param maxSize number
]=]
function MarketplaceServiceCache.SetMaxSize(self: MarketplaceServiceCache, maxSize: number)
	assert(type(maxSize) == "number" and maxSize >= 1 and maxSize % 1 == 0, "Bad maxSize")
	self._maxSize = maxSize
	self:_trimCache()
end

--[=[
	Returns a cached promise for `MarketplaceService:GetProductInfoAsync`. Calls
	with the same product ID and info type share the same in-flight request.

	Rejected requests are evicted automatically so transient Roblox failures can
	be retried.

	@within MarketplaceServiceCache
	@param productId number
	@param infoType Enum.InfoType
	@return Promise<ProductInfo>
]=]
function MarketplaceServiceCache.PromiseProductInfo(
	self: MarketplaceServiceCache,
	productId: number,
	infoType: Enum.InfoType
): Promise.Promise<ProductInfo>
	assert(type(productId) == "number" and productId > 0 and productId % 1 == 0, "Bad productId")
	assert(typeof(infoType) == "EnumItem" and infoType.EnumType == Enum.InfoType, "Bad infoType")

	const key = `{infoType.Name}:{productId}`
	self._accessCounter += 1

	const cached = self._cache[key]
	if cached then
		cached.lastAccess = self._accessCounter
		return cached.promise
	end

	const promise = MarketplaceUtils.promiseProductInfo(productId, infoType)
	self._cache[key] = {
		promise = promise,
		lastAccess = self._accessCounter,
	}

	-- Attaching a rejection handler also marks the source rejection as consumed.
	-- The original promise is still returned to callers with its rejection intact.
	promise:Catch(function()
		const current = self._cache[key]
		if current and current.promise == promise then
			self._cache[key] = nil
		end
	end)

	self:_trimCache()
	return promise
end

--[=[
	Returns a cached promise for
	`MarketplaceService:GetSubscriptionProductInfoAsync`. Calls for the same
	subscription share one in-flight request, and rejected requests can retry.

	@within MarketplaceServiceCache
	@param subscriptionId string
	@return Promise<SubscriptionProductInfo>
]=]
function MarketplaceServiceCache.PromiseSubscriptionProductInfo(
	self: MarketplaceServiceCache,
	subscriptionId: string
): Promise.Promise<
	MarketplaceUtils.SubscriptionProductInfo
>
	assert(type(subscriptionId) == "string" and subscriptionId ~= "", "Bad subscriptionId")

	const key = `Subscription:{subscriptionId}`
	self._accessCounter += 1

	const cached = self._cache[key]
	if cached then
		cached.lastAccess = self._accessCounter
		return cached.promise
	end

	const promise = MarketplaceUtils.promiseSubscriptionProductInfo(subscriptionId)
	self._cache[key] = {
		promise = promise,
		lastAccess = self._accessCounter,
	}

	promise:Catch(function()
		const current = self._cache[key]
		if current and current.promise == promise then
			self._cache[key] = nil
		end
	end)

	self:_trimCache()
	return promise
end

--[=[
	Removes one cached product-information request. An already running request is
	not cancelled, but the next lookup starts a new request.

	@within MarketplaceServiceCache
	@param productId number
	@param infoType Enum.InfoType
]=]
function MarketplaceServiceCache.InvalidateProductInfo(
	self: MarketplaceServiceCache,
	productId: number,
	infoType: Enum.InfoType
)
	assert(type(productId) == "number" and productId > 0 and productId % 1 == 0, "Bad productId")
	assert(typeof(infoType) == "EnumItem" and infoType.EnumType == Enum.InfoType, "Bad infoType")
	self._cache[`{infoType.Name}:{productId}`] = nil
end

--[=[
	Removes one cached subscription product-information request.

	@within MarketplaceServiceCache
	@param subscriptionId string
]=]
function MarketplaceServiceCache.InvalidateSubscriptionProductInfo(
	self: MarketplaceServiceCache,
	subscriptionId: string
): ()
	assert(type(subscriptionId) == "string" and subscriptionId ~= "", "Bad subscriptionId")
	self._cache[`Subscription:{subscriptionId}`] = nil
end

--[=[
	Clears every cached product-information request.

	@within MarketplaceServiceCache
]=]
function MarketplaceServiceCache.Clear(self: MarketplaceServiceCache)
	table.clear(self._cache)
end

function MarketplaceServiceCache._trimCache(self: MarketplaceServiceCache)
	local cacheSize = 0
	for _ in self._cache do
		cacheSize += 1
	end

	while cacheSize > self._maxSize do
		local oldestKey: string? = nil
		local oldestAccess = math.huge
		for key, entry in self._cache do
			if entry.lastAccess < oldestAccess then
				oldestAccess = entry.lastAccess
				oldestKey = key
			end
		end

		if not oldestKey then
			break
		end
		self._cache[oldestKey] = nil
		cacheSize -= 1
	end
end

function MarketplaceServiceCache.Destroy(self: MarketplaceServiceCache)
	table.clear(self._cache)
	self._maid:DoCleaning()
	table.clear(self)
	setmetatable(self, nil)
end

return MarketplaceServiceCache
