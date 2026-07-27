--!strict
--[=[
	Client purchase prompting and receipt-confirmed purchase observation.

	@class GameProductServiceClient
	@client
]=]

const MarketplaceService = game:GetService("MarketplaceService")
const Players = game:GetService("Players")

const require = require("../Loader").load()

const GameConfigAssetTypes = require("GameConfigAssetTypes")
const GameConfigServiceClient = require("GameConfigServiceClient")
const GameProductNetwork = require("GameProductNetwork")
const GameProductTypes = require("GameProductTypes")
const GameProductUtils = require("GameProductUtils")
const Maid = require("Maid")
const MarketplaceUtils = require("MarketplaceUtils")
const Observable = require("Observable")
const Promise = require("Promise")
const ServiceBag = require("ServiceBag")
const Signal = require("Signal")

const DEFAULT_PROMPT_TIMEOUT = 300

type AssetIdOrKey = GameProductTypes.AssetIdOrKey
type AssetType = GameProductTypes.AssetType
type OwnershipProvider = (number, string?) -> boolean? | Promise.Promise<boolean?>

type OwnershipProviderEntry = {
	assetType: AssetType,
	callback: OwnershipProvider,
	priority: number,
	timestamp: number,
}

type PendingPrompt = {
	assetType: AssetType,
	assetId: number,
	promise: Promise.Promise<boolean>,
	timeoutThread: thread,
}

const GameProductServiceClient = {}
GameProductServiceClient.ServiceName = "GameProductServiceClient"

export type GameProductServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_gameConfigService: GameConfigServiceClient.GameConfigServiceClient,
		_pendingPrompt: PendingPrompt?,
		_sessionPurchaseCounts: { [string]: { [number]: number } },
		_recordedPasses: { [number]: boolean },
		_ownershipProviders: { OwnershipProviderEntry },
		_registrationCounter: number,

		PurchaseGranted: Signal.Signal<string, number>,
		GamePassPurchased: Signal.Signal<number>,
		ProductPurchased: Signal.Signal<number>,
	},
	{} :: typeof({ __index = GameProductServiceClient })
))

function GameProductServiceClient.Init(self: GameProductServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._gameConfigService = self._serviceBag:GetService(GameConfigServiceClient)
	self._pendingPrompt = nil
	self._sessionPurchaseCounts = {}
	self._recordedPasses = {}
	self._ownershipProviders = {}
	self._registrationCounter = 0

	self.PurchaseGranted = self._maid:Add(Signal.new() :: any)
	self.GamePassPurchased = self._maid:Add(Signal.new() :: any)
	self.ProductPurchased = self._maid:Add(Signal.new() :: any)

	GameProductNetwork.packets.purchaseProcessed.listen(function(data)
		const assetType = GameProductUtils.codeToAssetType(data.assetType)
		if not assetType then
			return
		end
		if data.purchased then
			self:_recordPurchase(assetType, data.assetId)
		end
		self:_finishPending(assetType, data.assetId, data.purchased)
	end)
end

function GameProductServiceClient.Start(self: GameProductServiceClient): ()
	self._maid:Add(MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if player ~= Players.LocalPlayer or type(passId) ~= "number" or type(purchased) ~= "boolean" then
			return
		end
		-- The server also sends a successful result. Record here immediately for a
		-- responsive client, while _recordPurchase de-duplicates the same event.
		if purchased then
			self:_recordPurchase(GameConfigAssetTypes.PASS, passId)
		end
		self:_finishPending(GameConfigAssetTypes.PASS, passId, purchased)
	end))

	self._maid:Add(MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if userId ~= Players.LocalPlayer.UserId or type(productId) ~= "number" or type(purchased) ~= "boolean" then
			return
		end
		-- A true value only means the prompt attempted a purchase. ProcessReceipt on
		-- the server is the source of truth and sends purchaseProcessed on success.
		if not purchased then
			self:_finishPending(GameConfigAssetTypes.PRODUCT, productId, false)
		end
	end))
end

--[=[
	Prompts the local player for a configured pass or developer product.

	@within GameProductServiceClient
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@param timeout number?
	@return Promise<boolean>
]=]
function GameProductServiceClient.PromptPurchaseAsync(
	self: GameProductServiceClient,
	assetType: AssetType,
	idOrKey: AssetIdOrKey,
	timeout: number?
): Promise.Promise<boolean>
	assert(GameProductUtils.isProductAssetType(assetType), "Bad assetType")
	assert(type(idOrKey) == "number" or (type(idOrKey) == "string" and idOrKey ~= ""), "Bad idOrKey")
	assert(timeout == nil or type(timeout) == "number", "Bad timeout")
	if self._pendingPrompt then
		return Promise.rejected("A purchase prompt is already open")
	end

	local assetId = self:_resolveAsset(assetType, idOrKey)
	if not assetId then
		return Promise.rejected(`No configured {assetType} exists for {tostring(idOrKey)}`)
	end
	const resolvedTimeout = math.clamp(timeout or DEFAULT_PROMPT_TIMEOUT, 1, 900)
	const promise = self._maid:GivePromise(Promise.new()) :: Promise.Promise<boolean>
	local pending: PendingPrompt
	const timeoutThread = task.delay(resolvedTimeout, function()
		if self._pendingPrompt == pending then
			self._pendingPrompt = nil
			promise:Reject(`Purchase prompt timed out after {resolvedTimeout} seconds`)
		end
	end)
	pending = {
		assetType = assetType,
		assetId = assetId,
		promise = promise,
		timeoutThread = timeoutThread,
	}
	self._pendingPrompt = pending

	const success, errorMessage = pcall(function()
		if assetType == GameConfigAssetTypes.PASS then
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, assetId)
		else
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, assetId)
		end
	end)
	if not success then
		self._pendingPrompt = nil
		task.cancel(timeoutThread)
		promise:Reject(errorMessage)
	end
	return promise
end

--[=[
	Checks custom ownership providers, then normal pass ownership or whether a
	developer product was granted this client session.

	@within GameProductServiceClient
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@return Promise<boolean>
]=]
function GameProductServiceClient.HasAssetAsync(
	self: GameProductServiceClient,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Promise.Promise<boolean>
	assert(GameProductUtils.isProductAssetType(assetType), "Bad assetType")
	local assetId, assetKey = self:_resolveAsset(assetType, idOrKey)
	if not assetId then
		return Promise.rejected(`No configured {assetType} exists for {tostring(idOrKey)}`)
	end
	return Promise.spawn(function(resolve, reject)
		for _, provider in self._ownershipProviders do
			if provider.assetType ~= assetType then
				continue
			end
			local called, result = pcall(provider.callback, assetId, assetKey)
			if not called then
				reject(result)
				return
			end
			if Promise.isPromise(result) then
				local succeeded
				succeeded, result = (result :: Promise.Promise<any>):Yield()
				if not succeeded then
					reject(result)
					return
				end
			end
			if result == true then
				resolve(true)
				return
			end
		end
		if assetType == GameConfigAssetTypes.PRODUCT then
			resolve(self:GetPurchaseCountThisSession(assetType, assetId) > 0)
			return
		end
		local succeeded, owns = MarketplaceUtils.promiseUserOwnsGamePass(Players.LocalPlayer.UserId, assetId):Yield()
		if succeeded then
			resolve(owns)
		else
			reject(owns)
		end
	end)
end

--[=[
	Registers a local ownership source. Returning true owns the entitlement; false
	or nil falls through to later providers and normal ownership.

	@within GameProductServiceClient
	@param assetType "pass" | "product"
	@param callback (assetId, assetKey) -> boolean? | Promise<boolean?>
	@param priority number?
	@return () -> ()
]=]
function GameProductServiceClient.RegisterOwnershipProvider(
	self: GameProductServiceClient,
	assetType: AssetType,
	callback: OwnershipProvider,
	priority: number?
): () -> ()
	assert(GameProductUtils.isProductAssetType(assetType), "Bad assetType")
	assert(type(callback) == "function", "Bad callback")
	assert(priority == nil or type(priority) == "number", "Bad priority")
	self._registrationCounter += 1
	const entry: OwnershipProviderEntry = {
		assetType = assetType,
		callback = callback,
		priority = priority or 0,
		timestamp = self._registrationCounter,
	}
	table.insert(self._ownershipProviders, entry)
	table.sort(self._ownershipProviders, function(left, right)
		return if left.priority == right.priority
			then left.timestamp < right.timestamp
			else left.priority > right.priority
	end)

	local connected = true
	return function()
		if not connected then
			return
		end
		connected = false
		const index = table.find(self._ownershipProviders, entry)
		if index then
			table.remove(self._ownershipProviders, index)
		end
	end
end

--[=[
	Returns the number of successful purchases observed this client session.

	@within GameProductServiceClient
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@return number
]=]
function GameProductServiceClient.GetPurchaseCountThisSession(
	self: GameProductServiceClient,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): number
	assert(GameProductUtils.isProductAssetType(assetType), "Bad assetType")
	local assetId = self:_resolveAsset(assetType, idOrKey)
	if not assetId then
		return 0
	end
	return if self._sessionPurchaseCounts[assetType] then self._sessionPurchaseCounts[assetType][assetId] or 0 else 0
end

--[=[
	Observes successful purchases of a configured asset by the local player.

	@within GameProductServiceClient
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@return Observable<number>
]=]
function GameProductServiceClient.ObservePurchase(
	self: GameProductServiceClient,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Observable.Observable<number>
	assert(GameProductUtils.isProductAssetType(assetType), "Bad assetType")
	const assetId = assert(self:_resolveAsset(assetType, idOrKey), "Asset is not configured")
	return Observable.new(function(sub)
		return self.PurchaseGranted:Connect(function(purchasedType, purchasedId)
			if purchasedType == assetType and purchasedId == assetId then
				sub:Fire(purchasedId)
			end
		end)
	end)
end

--[=[
	Returns whether this client is currently tracking an open prompt.

	@within GameProductServiceClient
	@return boolean
]=]
function GameProductServiceClient.IsPromptOpen(self: GameProductServiceClient): boolean
	return self._pendingPrompt ~= nil
end

--[=[
	Compatibility wrapper that only accepts LocalPlayer.

	@within GameProductServiceClient
	@param player Player
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@return Promise<boolean>
]=]
function GameProductServiceClient.PromisePromptPurchase(
	self: GameProductServiceClient,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Promise.Promise<boolean>
	assert(player == Players.LocalPlayer, "Client can only prompt LocalPlayer")
	return self:PromptPurchaseAsync(assetType, idOrKey)
end

--[=[
	Compatibility ownership wrapper that only accepts LocalPlayer.

	@within GameProductServiceClient
	@param player Player
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@return Promise<boolean>
]=]
function GameProductServiceClient.PromisePlayerOwnership(
	self: GameProductServiceClient,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Promise.Promise<boolean>
	assert(player == Players.LocalPlayer, "Client can only query LocalPlayer")
	return self:HasAssetAsync(assetType, idOrKey)
end

function GameProductServiceClient._resolveAsset(
	self: GameProductServiceClient,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): (number?, string?)
	const picker = self._gameConfigService:GetConfigPicker()
	const resolved = picker:ToAssetId(assetType, idOrKey)
	if not (type(resolved) == "number" and resolved > 0 and resolved % 1 == 0 and resolved <= 2 ^ 32 - 1) then
		return nil, nil
	end
	const asset = picker:FindFirstActiveAssetOfId(assetType, resolved)
	return resolved, if asset then asset:GetAssetKey() else nil
end

function GameProductServiceClient._recordPurchase(
	self: GameProductServiceClient,
	assetType: AssetType,
	assetId: number
): ()
	if assetType == GameConfigAssetTypes.PASS then
		if self._recordedPasses[assetId] then
			return
		end
		self._recordedPasses[assetId] = true
	end

	local counts = self._sessionPurchaseCounts[assetType]
	if not counts then
		counts = {}
		self._sessionPurchaseCounts[assetType] = counts
	end
	-- A pass success is seen from both the local prompt event and the authoritative
	-- server packet. Passes are one-time, so keep that count at one.
	counts[assetId] = if assetType == GameConfigAssetTypes.PASS then 1 else (counts[assetId] or 0) + 1
	if assetType == GameConfigAssetTypes.PASS then
		self.GamePassPurchased:Fire(assetId)
	else
		self.ProductPurchased:Fire(assetId)
	end
	self.PurchaseGranted:Fire(assetType, assetId)
end

function GameProductServiceClient._finishPending(
	self: GameProductServiceClient,
	assetType: AssetType,
	assetId: number,
	purchased: boolean
): ()
	const pending = self._pendingPrompt
	if not pending or pending.assetType ~= assetType or pending.assetId ~= assetId then
		return
	end
	self._pendingPrompt = nil
	task.cancel(pending.timeoutThread)
	pending.promise:Resolve(purchased)
end

function GameProductServiceClient.Destroy(self: GameProductServiceClient): ()
	if self._pendingPrompt then
		task.cancel(self._pendingPrompt.timeoutThread)
		self._pendingPrompt.promise:Reject("GameProductServiceClient destroyed")
		self._pendingPrompt = nil
	end
	self._maid:Destroy()
end

return GameProductServiceClient
