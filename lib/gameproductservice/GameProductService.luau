--!strict
--[=[
	GameConfig-backed purchase prompting, ownership queries, and receipt-safe
	developer-product fulfillment.

	Developer products are granted only from ProcessReceipt through
	ReceiptProcessingService. PromptProductPurchaseFinished is used only to detect
	a cancelled prompt. Purchase handlers are prioritized and the first handler to
	return `grant` or `retry` claims the purchase.

	@class GameProductService
	@server
]=]

const MarketplaceService = game:GetService("MarketplaceService")
const Players = game:GetService("Players")

const require = require("../Loader").load()

const CmdrService = require("CmdrService")
const GameConfigAssetTypes = require("GameConfigAssetTypes")
const GameConfigService = require("GameConfigService")
const GameProductHandlerResult = require("GameProductHandlerResult")
const GameProductNetwork = require("GameProductNetwork")
const GameProductTypes = require("GameProductTypes")
const GameProductUtils = require("GameProductUtils")
const Maid = require("Maid")
const MarketplaceUtils = require("MarketplaceUtils")
const Observable = require("Observable")
const Promise = require("Promise")
const ReceiptProcessingService = require("ReceiptProcessingService")
const ServiceBag = require("ServiceBag")
const Signal = require("Signal")
const TableUtils = require("TableUtils")

const DEFAULT_PROMPT_TIMEOUT = 300
const MAX_PROMPT_TIMEOUT = 900

type AssetIdOrKey = GameProductTypes.AssetIdOrKey
type AssetType = GameProductTypes.AssetType
type PromptOptions = GameProductTypes.PromptOptions
type PurchaseContext = GameProductTypes.PurchaseContext
type HandlerResult = GameProductHandlerResult.GameProductHandlerResult
type PurchaseCallback = (PurchaseContext) -> HandlerResult | boolean | Promise.Promise<any> | nil
type OwnershipProvider = (Player, PurchaseContext) -> boolean? | Promise.Promise<boolean?>

type CallbackEntry = {
	assetType: AssetType?,
	idOrKey: AssetIdOrKey?,
	callback: PurchaseCallback,
	priority: number,
	timestamp: number,
	nilMeansGranted: boolean,
}

type OwnershipProviderEntry = {
	assetType: AssetType,
	callback: OwnershipProvider,
	priority: number,
	timestamp: number,
}

type PendingPrompt = {
	assetType: AssetType,
	assetId: number,
	assetKey: string?,
	context: { [string]: any }?,
	promise: Promise.Promise<boolean>,
	timeoutThread: thread,
}

type OwnershipCacheEntry = {
	promise: Promise.Promise<boolean>,
	expiresAt: number,
}

const GameProductService = {}
GameProductService.ServiceName = "GameProductService"
GameProductService.ServerOnly = true

export type GameProductService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_cmdrService: CmdrService.CmdrService,
		_gameConfigService: GameConfigService.GameConfigService,
		_receiptProcessingService: ReceiptProcessingService.ReceiptProcessingService,
		_callbacks: { CallbackEntry },
		_ownershipProviders: { OwnershipProviderEntry },
		_pendingPrompts: { [Player]: PendingPrompt },
		_sessionPurchaseCounts: { [Player]: { [string]: { [number]: number } } },
		_ownershipCache: { [Player]: { [number]: OwnershipCacheEntry } },
		_registrationCounter: number,

		PurchaseGranted: Signal.Signal<Player, string, number, PurchaseContext>,
		GamePassPurchased: Signal.Signal<Player, number, PurchaseContext>,
		ProductPurchased: Signal.Signal<Player, number, PurchaseContext>,
	},
	{} :: typeof({ __index = GameProductService })
))

function GameProductService.Init(self: GameProductService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._cmdrService = self._serviceBag:GetService(CmdrService)
	self._gameConfigService = self._serviceBag:GetService(GameConfigService)
	self._receiptProcessingService = self._serviceBag:GetService(ReceiptProcessingService)
	self._callbacks = {}
	self._ownershipProviders = {}
	self._pendingPrompts = setmetatable({}, { __mode = "k" }) :: any
	self._sessionPurchaseCounts = setmetatable({}, { __mode = "k" }) :: any
	self._ownershipCache = setmetatable({}, { __mode = "k" }) :: any
	self._registrationCounter = 0

	self.PurchaseGranted = self._maid:Add(Signal.new() :: any)
	self.GamePassPurchased = self._maid:Add(Signal.new() :: any)
	self.ProductPurchased = self._maid:Add(Signal.new() :: any)

	-- Unknown or unhandled developer products must retry instead of being silently
	-- consumed. A game can still deliberately change this after initialization.
	self._receiptProcessingService:SetDefaultPurchaseDecision(Enum.ProductPurchaseDecision.NotProcessedYet)
	self._maid:Add(self._receiptProcessingService:RegisterReceiptProcessor(function(receiptInfo)
		const succeeded, result = pcall(function()
			return self:_processReceipt(receiptInfo :: any)
		end)
		if not succeeded then
			warn(`[GameProductService] - Receipt processing failed and will retry: {result}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return result
	end, 100))
end

function GameProductService.Start(self: GameProductService): ()
	self._maid:Add(MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if typeof(player) == "Instance" and player:IsA("Player") then
			self:_handlePassPromptFinished(player, gamePassId, purchased)
		end
	end))

	self._maid:Add(MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if type(userId) ~= "number" or type(productId) ~= "number" or type(purchased) ~= "boolean" then
			return
		end
		const player = Players:GetPlayerByUserId(userId)
		if player and not purchased then
			self:_finishPendingPrompt(player, GameConfigAssetTypes.PRODUCT, productId, false)
		end
	end))

	self._maid:Add(Players.PlayerRemoving:Connect(function(player)
		const pending = self._pendingPrompts[player]
		if pending then
			self._pendingPrompts[player] = nil
			task.cancel(pending.timeoutThread)
			pending.promise:Reject("Player left before the purchase completed")
		end
		self._sessionPurchaseCounts[player] = nil
		self._ownershipCache[player] = nil
	end))

	self._cmdrService:RegisterCommand({
		Name = "prompt-product",
		Description = "Prompts one or more players to buy a configured developer product.",
		Group = "GameConfig",
		Args = {
			{ Type = "players", Name = "players", Description = "Players to prompt." },
			{ Type = "product", Name = "product", Description = "Configured product key or ID." },
		},
	}, function(_, players: { Player }, productId: number)
		local prompted = 0
		const failures = {}
		for _, player in players do
			if self:IsPromptOpen(player) then
				table.insert(failures, `{player.Name}: another purchase prompt is already open`)
				continue
			end
			const called, promptOrError = pcall(function()
				return self:PromptPurchaseAsync(player, GameConfigAssetTypes.PRODUCT, productId)
			end)
			if not called then
				table.insert(failures, `{player.Name}: {tostring(promptOrError)}`)
				continue
			end
			const prompt = promptOrError :: Promise.Promise<boolean>
			if prompt:IsRejected() then
				local _, reason = prompt:GetResults()
				table.insert(failures, `{player.Name}: {tostring(reason)}`)
				continue
			end
			prompted += 1
			prompt:Catch(function(reason)
				warn(`[GameProductService] - Product prompt for {player.Name} ended with: {reason}`)
			end)
		end
		if #failures == 0 then
			return `Opened product {productId} prompt for {prompted} player(s).`
		elseif prompted == 0 then
			return `Could not open any product prompts: {table.concat(failures, "; ")}.`
		end
		return `Opened {prompted} product prompt(s); failed {#failures}: {table.concat(failures, "; ")}.`
	end)

	self._cmdrService:RegisterCommand({
		Name = "prompt-pass",
		Description = "Prompts one or more players to buy a configured game pass.",
		Group = "GameConfig",
		Args = {
			{ Type = "players", Name = "players", Description = "Players to prompt." },
			{ Type = "gamepass", Name = "pass", Description = "Configured pass key or ID." },
		},
	}, function(_, players: { Player }, passId: number)
		local prompted = 0
		const failures = {}
		for _, player in players do
			if self:IsPromptOpen(player) then
				table.insert(failures, `{player.Name}: another purchase prompt is already open`)
				continue
			end
			const called, promptOrError = pcall(function()
				return self:PromptPurchaseAsync(player, GameConfigAssetTypes.PASS, passId)
			end)
			if not called then
				table.insert(failures, `{player.Name}: {tostring(promptOrError)}`)
				continue
			end
			const prompt = promptOrError :: Promise.Promise<boolean>
			if prompt:IsRejected() then
				local _, reason = prompt:GetResults()
				table.insert(failures, `{player.Name}: {tostring(reason)}`)
				continue
			end
			prompted += 1
			prompt:Catch(function(reason)
				warn(`[GameProductService] - Pass prompt for {player.Name} ended with: {reason}`)
			end)
		end
		if #failures == 0 then
			return `Opened game-pass {passId} prompt for {prompted} player(s).`
		elseif prompted == 0 then
			return `Could not open any game-pass prompts: {table.concat(failures, "; ")}.`
		end
		return `Opened {prompted} game-pass prompt(s); failed {#failures}: {table.concat(failures, "; ")}.`
	end)
end

--[=[
	Registers a handler for one configured pass or product. The first matching
	handler to grant or retry claims the purchase. A successful callback that
	returns nil is treated as granted for this keyed convenience API.

	@within GameProductService
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@param callback PurchaseCallback
	@param priority number?
	@return () -> ()
]=]
function GameProductService.RegisterPurchaseCallback(
	self: GameProductService,
	assetType: AssetType,
	idOrKey: AssetIdOrKey,
	callback: PurchaseCallback,
	priority: number?
): () -> ()
	assert(GameProductUtils.isProductAssetType(assetType), "Bad assetType")
	assert(type(idOrKey) == "number" or (type(idOrKey) == "string" and idOrKey ~= ""), "Bad idOrKey")
	assert(type(callback) == "function", "Bad callback")
	assert(priority == nil or type(priority) == "number", "Bad priority")
	return self:_registerCallback(assetType, idOrKey, callback, priority or 0, true)
end

--[=[
	Registers a developer-product fulfillment callback.

	@within GameProductService
	@param idOrKey number | string
	@param callback PurchaseCallback
	@param priority number?
	@return () -> ()
]=]
function GameProductService.RegisterProductCallback(
	self: GameProductService,
	idOrKey: AssetIdOrKey,
	callback: PurchaseCallback,
	priority: number?
): () -> ()
	return self:RegisterPurchaseCallback(GameConfigAssetTypes.PRODUCT, idOrKey, callback, priority)
end

--[=[
	Registers a game-pass post-purchase callback.

	@within GameProductService
	@param idOrKey number | string
	@param callback PurchaseCallback
	@param priority number?
	@return () -> ()
]=]
function GameProductService.RegisterPassCallback(
	self: GameProductService,
	idOrKey: AssetIdOrKey,
	callback: PurchaseCallback,
	priority: number?
): () -> ()
	return self:RegisterPurchaseCallback(GameConfigAssetTypes.PASS, idOrKey, callback, priority)
end

--[=[
	Registers middleware for every pass and product purchase. Return `skip` to let
	later handlers run, `grant` after durable fulfillment, or `retry` when a
	developer-product receipt must be attempted again.

	@within GameProductService
	@param callback PurchaseCallback
	@param priority number?
	@return () -> ()
]=]
function GameProductService.RegisterPurchaseProcessor(
	self: GameProductService,
	callback: PurchaseCallback,
	priority: number?
): () -> ()
	assert(type(callback) == "function", "Bad callback")
	assert(priority == nil or type(priority) == "number", "Bad priority")
	return self:_registerCallback(nil, nil, callback, priority or 0, false)
end

--[=[
	Registers an additional ownership source. Returning true owns the entitlement;
	false or nil falls through to later providers and Roblox ownership.

	@within GameProductService
	@param assetType "pass" | "product"
	@param callback OwnershipProvider
	@param priority number?
	@return () -> ()
]=]
function GameProductService.RegisterOwnershipProvider(
	self: GameProductService,
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
	Prompts a configured pass or developer product. Options may attach a server-only
	context table used by fulfillment handlers and set a timeout.

	@within GameProductService
	@param player Player
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@param options PromptOptions?
	@return Promise<boolean>
]=]
function GameProductService.PromptPurchaseAsync(
	self: GameProductService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey,
	options: PromptOptions?
): Promise.Promise<boolean>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(player.Parent == Players, "Player is not in this server")
	assert(GameProductUtils.isProductAssetType(assetType), "Bad assetType")
	assert(type(idOrKey) == "number" or (type(idOrKey) == "string" and idOrKey ~= ""), "Bad idOrKey")
	assert(options == nil or type(options) == "table", "Bad options")
	if options then
		assert(options.Context == nil or type(options.Context) == "table", "Bad options.Context")
		assert(options.Timeout == nil or type(options.Timeout) == "number", "Bad options.Timeout")
	end

	if self._pendingPrompts[player] then
		return Promise.rejected(`A purchase prompt is already open for {player.Name}`)
	end

	local assetId, assetKey = self:_resolveAsset(assetType, idOrKey)
	if not assetId then
		return Promise.rejected(`No configured {assetType} exists for {tostring(idOrKey)}`)
	end

	const timeout = math.clamp(options and options.Timeout or DEFAULT_PROMPT_TIMEOUT, 1, MAX_PROMPT_TIMEOUT)
	const promise = self._maid:GivePromise(Promise.new()) :: Promise.Promise<boolean>
	local pending: PendingPrompt
	const timeoutThread = task.delay(timeout, function()
		if self._pendingPrompts[player] == pending then
			self._pendingPrompts[player] = nil
			promise:Reject(`Purchase prompt timed out after {timeout} seconds`)
		end
	end)
	pending = {
		assetType = assetType,
		assetId = assetId,
		assetKey = assetKey,
		context = if options and options.Context then TableUtils.deepCopy(options.Context) else nil,
		promise = promise,
		timeoutThread = timeoutThread,
	}
	self._pendingPrompts[player] = pending

	const success, errorMessage = pcall(function()
		if assetType == GameConfigAssetTypes.PASS then
			MarketplaceService:PromptGamePassPurchase(player, assetId)
		else
			MarketplaceService:PromptProductPurchase(player, assetId)
		end
	end)
	if not success then
		self._pendingPrompts[player] = nil
		task.cancel(timeoutThread)
		promise:Reject(errorMessage)
	end

	return promise
end

--[=[
	Checks custom ownership providers and then normal Roblox ownership. Developer
	products are considered owned only if a provider says so or they were granted
	during this server session.

	@within GameProductService
	@param player Player
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@return Promise<boolean>
]=]
function GameProductService.HasAssetAsync(
	self: GameProductService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Promise.Promise<boolean>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(GameProductUtils.isProductAssetType(assetType), "Bad assetType")
	assert(type(idOrKey) == "number" or (type(idOrKey) == "string" and idOrKey ~= ""), "Bad idOrKey")

	local assetId, assetKey = self:_resolveAsset(assetType, idOrKey)
	if not assetId then
		return Promise.rejected(`No configured {assetType} exists for {tostring(idOrKey)}`)
	end

	const context: PurchaseContext = {
		Player = player,
		AssetType = assetType,
		AssetId = assetId,
		AssetKey = assetKey,
		PromptContext = nil,
		ReceiptInfo = nil,
	}

	return Promise.spawn(function(resolve, reject)
		for _, provider in self._ownershipProviders do
			if provider.assetType ~= assetType then
				continue
			end
			local called, result = pcall(provider.callback, player, context)
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
			resolve(self:GetPurchaseCountThisSession(player, assetType, assetId) > 0)
			return
		end

		local playerCache = self._ownershipCache[player]
		if not playerCache then
			playerCache = {}
			self._ownershipCache[player] = playerCache
		end
		const cached = playerCache[assetId]
		if cached and cached.expiresAt > os.clock() then
			local succeeded, owns = cached.promise:Yield()
			if succeeded then
				resolve(owns)
			else
				reject(owns)
			end
			return
		end

		const ownershipPromise = MarketplaceUtils.promiseUserOwnsGamePass(player.UserId, assetId)
		playerCache[assetId] = {
			promise = ownershipPromise,
			expiresAt = os.clock() + 30,
		}
		local succeeded, owns = ownershipPromise:Yield()
		if succeeded then
			if owns then
				playerCache[assetId] = {
					promise = Promise.resolved(true),
					expiresAt = math.huge,
				}
			end
			resolve(owns)
		else
			playerCache[assetId] = nil
			reject(owns)
		end
	end)
end

--[=[
	Returns how many successful purchases were observed in this server session.

	@within GameProductService
	@param player Player
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@return number
]=]
function GameProductService.GetPurchaseCountThisSession(
	self: GameProductService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): number
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(GameProductUtils.isProductAssetType(assetType), "Bad assetType")
	local assetId = self:_resolveAsset(assetType, idOrKey)
	if not assetId then
		return 0
	end
	const playerCounts = self._sessionPurchaseCounts[player]
	return if playerCounts and playerCounts[assetType] then playerCounts[assetType][assetId] or 0 else 0
end

--[=[
	Returns whether a purchase prompt is currently tracked for a player.

	@within GameProductService
	@param player Player
	@return boolean
]=]
function GameProductService.IsPromptOpen(self: GameProductService, player: Player): boolean
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	return self._pendingPrompts[player] ~= nil
end

--[=[
	Returns a copy of the server-only context attached to a pending prompt.

	@within GameProductService
	@param player Player
	@return table?
]=]
function GameProductService.GetPendingPromptContext(self: GameProductService, player: Player): { [string]: any }?
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	const pending = self._pendingPrompts[player]
	return if pending and pending.context then TableUtils.deepCopy(pending.context) else nil
end

--[=[
	Observes matching successful purchases.

	@within GameProductService
	@param player Player
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@return Observable<PurchaseContext>
]=]
function GameProductService.ObservePlayerPurchase(
	self: GameProductService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Observable.Observable<PurchaseContext>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(GameProductUtils.isProductAssetType(assetType), "Bad assetType")
	local assetId = assert(self:_resolveAsset(assetType, idOrKey), "Asset is not configured")

	return Observable.new(function(sub)
		return self.PurchaseGranted:Connect(function(purchasedPlayer, purchasedType, purchasedId, context)
			if purchasedPlayer == player and purchasedType == assetType and purchasedId == assetId then
				sub:Fire(context)
			end
		end)
	end)
end

--[=[
	Clears a cached normal game-pass ownership query.

	@within GameProductService
	@param player Player
	@param idOrKey number | string
]=]
function GameProductService.InvalidateOwnership(self: GameProductService, player: Player, idOrKey: AssetIdOrKey): ()
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	local assetId = self:_resolveAsset(GameConfigAssetTypes.PASS, idOrKey)
	if assetId and self._ownershipCache[player] then
		self._ownershipCache[player][assetId] = nil
	end
end

--[=[
	Compatibility wrapper for PromptPurchaseAsync.

	@within GameProductService
	@param player Player
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@return Promise<boolean>
]=]
function GameProductService.PromisePlayerPromptPurchase(
	self: GameProductService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Promise.Promise<boolean>
	return self:PromptPurchaseAsync(player, assetType, idOrKey)
end

--[=[
	Compatibility wrapper for HasAssetAsync.

	@within GameProductService
	@param player Player
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@return Promise<boolean>
]=]
function GameProductService.PromisePlayerOwnership(
	self: GameProductService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Promise.Promise<boolean>
	return self:HasAssetAsync(player, assetType, idOrKey)
end

--[=[
	Compatibility boolean for session purchase state.

	@within GameProductService
	@param player Player
	@param assetType "pass" | "product"
	@param idOrKey number | string
	@return boolean
]=]
function GameProductService.HasPlayerPurchasedThisSession(
	self: GameProductService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): boolean
	return self:GetPurchaseCountThisSession(player, assetType, idOrKey) > 0
end

function GameProductService._registerCallback(
	self: GameProductService,
	assetType: AssetType?,
	idOrKey: AssetIdOrKey?,
	callback: PurchaseCallback,
	priority: number,
	nilMeansGranted: boolean
): () -> ()
	self._registrationCounter += 1
	const entry: CallbackEntry = {
		assetType = assetType,
		idOrKey = idOrKey,
		callback = callback,
		priority = priority,
		timestamp = self._registrationCounter,
		nilMeansGranted = nilMeansGranted,
	}
	table.insert(self._callbacks, entry)
	table.sort(self._callbacks, function(left, right)
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
		const index = table.find(self._callbacks, entry)
		if index then
			table.remove(self._callbacks, index)
		end
	end
end

function GameProductService._resolveAsset(
	self: GameProductService,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): (number?, string?)
	const picker = self._gameConfigService:GetConfigPicker()
	const resolved = picker:ToAssetId(assetType, idOrKey)
	if type(resolved) ~= "number" or resolved <= 0 or resolved % 1 ~= 0 or resolved > 2 ^ 32 - 1 then
		return nil, nil
	end
	const asset = picker:FindFirstActiveAssetOfId(assetType, resolved)
	return resolved, if asset then asset:GetAssetKey() else nil
end

function GameProductService._matchesCallback(
	_self: GameProductService,
	entry: CallbackEntry,
	context: PurchaseContext
): boolean
	if entry.assetType and entry.assetType ~= context.AssetType then
		return false
	end
	if entry.idOrKey == nil then
		return true
	end
	if type(entry.idOrKey) == "string" then
		return entry.idOrKey == context.AssetKey
	end
	return entry.idOrKey == context.AssetId
end

function GameProductService._dispatchCallbacks(self: GameProductService, context: PurchaseContext): HandlerResult
	for _, entry in self._callbacks do
		if not self:_matchesCallback(entry, context) then
			continue
		end

		local succeeded, result = pcall(entry.callback, context)
		if not succeeded then
			warn(`[GameProductService] - Purchase callback failed: {result}`)
			return GameProductHandlerResult.RETRY
		end
		if Promise.isPromise(result) then
			succeeded, result = (result :: Promise.Promise<any>):Yield()
			if not succeeded then
				warn(`[GameProductService] - Purchase callback promise failed: {result}`)
				return GameProductHandlerResult.RETRY
			end
		end

		if result == GameProductHandlerResult.GRANT or result == true or (result == nil and entry.nilMeansGranted) then
			return GameProductHandlerResult.GRANT
		elseif result == GameProductHandlerResult.RETRY or result == false then
			return GameProductHandlerResult.RETRY
		elseif result ~= nil and result ~= GameProductHandlerResult.SKIP then
			warn(`[GameProductService] - Invalid purchase callback result {tostring(result)}; retrying safely`)
			return GameProductHandlerResult.RETRY
		end
	end
	return GameProductHandlerResult.SKIP
end

function GameProductService._processReceipt(self: GameProductService, receiptInfo: { [string]: any }): any
	if type(receiptInfo) ~= "table" then
		return nil
	end
	const userId = receiptInfo.PlayerId
	const productId = receiptInfo.ProductId
	if type(userId) ~= "number" or type(productId) ~= "number" then
		return nil
	end
	if productId <= 0 or productId % 1 ~= 0 or productId > 2 ^ 32 - 1 then
		return nil
	end
	const player = Players:GetPlayerByUserId(userId)
	if not player then
		return nil
	end

	const pending = self._pendingPrompts[player]
	const asset =
		self._gameConfigService:GetConfigPicker():FindFirstActiveAssetOfId(GameConfigAssetTypes.PRODUCT, productId)
	const context: PurchaseContext = {
		Player = player,
		AssetType = GameConfigAssetTypes.PRODUCT,
		AssetId = productId,
		AssetKey = if asset then asset:GetAssetKey() else nil,
		PromptContext = if pending
				and pending.assetType == GameConfigAssetTypes.PRODUCT
				and pending.assetId == productId
			then TableUtils.deepCopy(pending.context)
			else nil,
		ReceiptInfo = TableUtils.deepCopy(receiptInfo),
	}
	const result = self:_dispatchCallbacks(context)
	if result == GameProductHandlerResult.SKIP then
		return nil
	elseif result == GameProductHandlerResult.RETRY then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	const notified, notificationError = pcall(function()
		self:_recordPurchase(player, GameConfigAssetTypes.PRODUCT, productId, context)
		self:_finishPendingPrompt(player, GameConfigAssetTypes.PRODUCT, productId, true)
	end)
	if not notified then
		warn(`[GameProductService] - Product was granted but purchase notification failed: {notificationError}`)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function GameProductService._handlePassPromptFinished(
	self: GameProductService,
	player: Player,
	passId: any,
	purchased: any
): ()
	if type(passId) ~= "number" or type(purchased) ~= "boolean" then
		return
	end
	if not purchased then
		self:_finishPendingPrompt(player, GameConfigAssetTypes.PASS, passId, false)
		return
	end

	const pending = self._pendingPrompts[player]
	const asset = self._gameConfigService:GetConfigPicker():FindFirstActiveAssetOfId(GameConfigAssetTypes.PASS, passId)
	const context: PurchaseContext = {
		Player = player,
		AssetType = GameConfigAssetTypes.PASS,
		AssetId = passId,
		AssetKey = if asset then asset:GetAssetKey() else nil,
		PromptContext = if pending
				and pending.assetType == GameConfigAssetTypes.PASS
				and pending.assetId == passId
			then TableUtils.deepCopy(pending.context)
			else nil,
		ReceiptInfo = nil,
	}
	const result = self:_dispatchCallbacks(context)
	if result == GameProductHandlerResult.RETRY then
		warn(`[GameProductService] - Pass callback requested a retry, but game-pass prompts have no retryable receipt`)
	end
	self:_recordPurchase(player, GameConfigAssetTypes.PASS, passId, context)
	self:_finishPendingPrompt(player, GameConfigAssetTypes.PASS, passId, true)
end

function GameProductService._recordPurchase(
	self: GameProductService,
	player: Player,
	assetType: AssetType,
	assetId: number,
	context: PurchaseContext
): ()
	local playerCounts = self._sessionPurchaseCounts[player]
	if not playerCounts then
		playerCounts = {}
		self._sessionPurchaseCounts[player] = playerCounts
	end
	local typeCounts = playerCounts[assetType]
	if not typeCounts then
		typeCounts = {}
		playerCounts[assetType] = typeCounts
	end
	typeCounts[assetId] = (typeCounts[assetId] or 0) + 1

	if assetType == GameConfigAssetTypes.PASS then
		local cache = self._ownershipCache[player]
		if not cache then
			cache = {}
			self._ownershipCache[player] = cache
		end
		cache[assetId] = { promise = Promise.resolved(true), expiresAt = math.huge }
		self.GamePassPurchased:Fire(player, assetId, context)
	else
		self.ProductPurchased:Fire(player, assetId, context)
	end
	self.PurchaseGranted:Fire(player, assetType, assetId, context)
	GameProductNetwork.packets.purchaseProcessed.sendTo({
		assetType = GameProductUtils.assetTypeToCode(assetType),
		assetId = assetId,
		purchased = true,
	}, player)
end

function GameProductService._finishPendingPrompt(
	self: GameProductService,
	player: Player,
	assetType: AssetType,
	assetId: number,
	purchased: boolean
): ()
	const pending = self._pendingPrompts[player]
	if not pending or pending.assetType ~= assetType or pending.assetId ~= assetId then
		if not purchased then
			GameProductNetwork.packets.purchaseProcessed.sendTo({
				assetType = GameProductUtils.assetTypeToCode(assetType),
				assetId = assetId,
				purchased = false,
			}, player)
		end
		return
	end
	self._pendingPrompts[player] = nil
	task.cancel(pending.timeoutThread)
	pending.promise:Resolve(purchased)
	if not purchased then
		GameProductNetwork.packets.purchaseProcessed.sendTo({
			assetType = GameProductUtils.assetTypeToCode(assetType),
			assetId = assetId,
			purchased = false,
		}, player)
	end
end

function GameProductService.Destroy(self: GameProductService): ()
	for player, pending in self._pendingPrompts do
		self._pendingPrompts[player] = nil
		task.cancel(pending.timeoutThread)
		pending.promise:Reject("GameProductService destroyed")
	end
	self._maid:Destroy()
end

return GameProductService
