--!strict
--[=[
	Persists GameConfig-backed pass and developer-product gifts, applies social
	restrictions, and integrates paid gift fulfillment with GameProductService.

	@class GiftingService
	@server
]=]

const HttpService = game:GetService("HttpService")
const Players = game:GetService("Players")
const CmdrService = require("@game/ReplicatedStorage/Packages/CmdrService")
const FriendUtils = require("@game/ReplicatedStorage/Packages/FriendUtils")
const GameConfigAssetTypes = require("@game/ReplicatedStorage/Packages/GameConfigAssetTypes")
const GameConfigService = require("@game/ReplicatedStorage/Packages/GameConfigService")
const GameProductHandlerResult = require("@game/ReplicatedStorage/Packages/GameProductHandlerResult")
const GameProductService = require("@game/ReplicatedStorage/Packages/GameProductService")
const GiftingAssetTypes = require("./Shared/GiftingAssetTypes")
const GiftingConstants = require("./Shared/GiftingConstants")
const GiftingDuplicateBehavior = require("./Shared/GiftingDuplicateBehavior")
const GiftingNetwork = require("./Shared/GiftingNetwork")
const GiftingRestrictions = require("./Shared/GiftingRestrictions")
const GiftingSerializationUtils = require("./Shared/GiftingSerializationUtils")
const GiftingTypes = require("./Shared/GiftingTypes")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const ObservableMap = require("@game/ReplicatedStorage/Packages/ObservableMap")
const PlayerDataStoreService = require("@game/ReplicatedStorage/Packages/PlayerDataStoreService")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const RxBrioUtils = require("@game/ReplicatedStorage/Packages/RxBrioUtils")
const RxPlayerUtils = require("@game/ReplicatedStorage/Packages/RxPlayerUtils")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

type AssetType = GiftingTypes.GiftingAssetType
type DuplicateBehavior = GiftingTypes.GiftingDuplicateBehavior
type GiftOptions = GiftingTypes.GiftOptions
type GiftRecord = GiftingTypes.GiftRecord
type PromptGiftOptions = GiftingTypes.PromptGiftOptions
type Restriction = GiftingTypes.GiftingRestriction

type PendingPurchase = {
	ContextId: string,
	RecipientUserId: number,
	AssetKey: string,
	AssetType: AssetType,
	PurchaseProductId: number,
	CreatedAt: number,
	Quantity: number,
	DuplicateBehavior: DuplicateBehavior,
	Metadata: { [string]: any },
}

type GiftRoot = {
	Entitlements: { [string]: GiftRecord },
	PendingPurchases: { [string]: PendingPurchase },
	ProcessedPurchases: { [string]: number },
}

type GiftProductMapping = {
	purchaseProduct: number | string,
	assetType: AssetType?,
}

const GiftingService = {}
GiftingService.ServiceName = "GiftingService"
GiftingService.ServerOnly = true

export type GiftingService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_cmdrService: CmdrService.CmdrService,
		_playerDataStoreService: PlayerDataStoreService.PlayerDataStoreService,
		_gameConfigService: GameConfigService.GameConfigService,
		_gameProductService: GameProductService.GameProductService,
		_defaultRestriction: Restriction,
		_playerRestrictions: { [Player]: Restriction },
		_giftRoots: { [Player]: GiftRoot },
		_giftMaps: { [Player]: ObservableMap.ObservableMap<string, GiftRecord> },
		_readyPromises: { [Player]: Promise.Promise<GiftRoot> },
		_sequences: { [Player]: number },
		_giftProductMappings: { [string]: GiftProductMapping },
	},
	{} :: typeof({ __index = GiftingService })
))

function GiftingService.Init(self: GiftingService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._cmdrService = self._serviceBag:GetService(CmdrService)
	self._gameConfigService = self._serviceBag:GetService(GameConfigService)
	self._gameProductService = self._serviceBag:GetService(GameProductService)
	self._playerDataStoreService = self._serviceBag:GetService(PlayerDataStoreService)
	self._defaultRestriction = GiftingRestrictions.All
	self._playerRestrictions = setmetatable({}, { __mode = "k" }) :: any
	self._giftRoots = setmetatable({}, { __mode = "k" }) :: any
	self._giftMaps = setmetatable({}, { __mode = "k" }) :: any
	self._readyPromises = setmetatable({}, { __mode = "k" }) :: any
	self._sequences = setmetatable({}, { __mode = "k" }) :: any
	self._giftProductMappings = {}

	self._playerDataStoreService:SetHiddenKey(GiftingConstants.ROOT_PATH)
	self._playerDataStoreService:AddReplicator(GiftingConstants.ROOT_PATH, function(player)
		self:_synchronizePlayer(player, true)
	end)

	self._maid:Add(self._gameProductService:RegisterPurchaseProcessor(function(context)
		return self:_processGiftPurchase(context)
	end, 1000))
	self._maid:Add(
		self._gameProductService:RegisterOwnershipProvider(GameConfigAssetTypes.PASS, function(player, context)
			return self:HasGiftAsync(player, context.AssetKey or tostring(context.AssetId))
		end, 1000)
	)
	self._maid:Add(
		self._gameProductService:RegisterOwnershipProvider(GameConfigAssetTypes.PRODUCT, function(player, context)
			return self:HasGiftAsync(player, context.AssetKey or tostring(context.AssetId))
		end, 1000)
	)
end

function GiftingService.Start(self: GiftingService): ()
	self._maid:Add(RxPlayerUtils.observePlayersBrio():Subscribe(function(brio)
		const maid, player = brio:ToMaidAndValue()
		maid:GivePromise(self:_getReadyPromise(player)):Catch(function(errorMessage)
			warn(`[GiftingService] - Failed to initialize {player.Name}: {errorMessage}`)
		end)
		maid:Add(function()
			const giftMap = self._giftMaps[player]
			if giftMap then
				giftMap:Destroy()
			end
			self._playerRestrictions[player] = nil
			self._giftRoots[player] = nil
			self._giftMaps[player] = nil
			self._readyPromises[player] = nil
			self._sequences[player] = nil
		end)
	end))

	GiftingNetwork.queries.getGifts.listen(function(_, player: Player?)
		if not player then
			return GiftingSerializationUtils.serialize(0, {})
		end
		const ready, root = self:_getReadyPromise(player):Yield()
		if not ready then
			warn(`[GiftingService] - Failed to answer gift query for {player.Name}: {root}`)
			return GiftingSerializationUtils.serialize(0, {})
		end
		const currentRoot = self._giftRoots[player]
		return GiftingSerializationUtils.serialize(
			self._sequences[player] or 0,
			if currentRoot then currentRoot.Entitlements else {}
		)
	end)

	self._cmdrService:RegisterCommand({
		Name = "gift",
		Aliases = { "grant-gift" },
		Description = "Grants a configured pass or product gift.",
		Group = "Gifting",
		Args = {
			{ Type = "players", Name = "players", Description = "Gift recipients." },
			{ Type = "giftAssetKey", Name = "assetKey", Description = "Configured pass or product key." },
			{ Type = "positiveInteger", Name = "quantity", Description = "Optional quantity.", Optional = true },
		},
	}, function(context, players: { Player }, assetKey: string, quantity: number?)
		local grantedCount = 0
		const failures = {}
		for _, player in players do
			const granted, result = self:GiftAsync(player, assetKey, {
				GiftedBy = context.Executor,
				Quantity = quantity,
				BypassRestriction = true,
				Metadata = { Source = "Cmdr" },
			}):Yield()
			if not granted then
				table.insert(failures, `{player.Name}: {tostring(result)}`)
			else
				grantedCount += 1
			end
		end
		if #failures == 0 then
			return `Gifted {assetKey} to {grantedCount} player(s).`
		elseif grantedCount == 0 then
			return `Could not gift {assetKey}: {table.concat(failures, "; ")}.`
		end
		return `Gifted {assetKey} to {grantedCount}; failed {#failures}: {table.concat(failures, "; ")}.`
	end)

	self._cmdrService:RegisterCommand({
		Name = "remove-gift",
		Description = "Removes or decrements a configured gift.",
		Group = "Gifting",
		Args = {
			{ Type = "players", Name = "players", Description = "Gift owners." },
			{ Type = "string", Name = "assetKey", Description = "Configured gift key." },
			{
				Type = "positiveInteger",
				Name = "quantity",
				Description = "Optional amount to remove.",
				Optional = true,
			},
		},
	}, function(_, players: { Player }, assetKey: string, quantity: number?)
		local removed = 0
		local missing = 0
		const failures = {}
		for _, player in players do
			const succeeded, didRemove = self:RemoveGiftAsync(player, assetKey, quantity):Yield()
			if not succeeded then
				table.insert(failures, `{player.Name}: {tostring(didRemove)}`)
			elseif didRemove then
				removed += 1
			else
				missing += 1
			end
		end
		if #failures > 0 then
			return `Removed {removed}, not found for {missing}, failed {#failures}: {table.concat(failures, "; ")}.`
		end
		return `Removed {assetKey} from {removed} player(s); not found for {missing}.`
	end)

	self._cmdrService:RegisterCommand({
		Name = "has-gift",
		Description = "Checks whether a player has a configured gift.",
		Group = "Gifting",
		Args = {
			{ Type = "player", Name = "player", Description = "Gift owner." },
			{ Type = "string", Name = "assetKey", Description = "Configured gift key." },
		},
	}, function(_, player: Player, assetKey: string)
		const succeeded, hasGift = self:HasGiftAsync(player, assetKey):Yield()
		if not succeeded then
			return `Could not check {player.Name}'s gift {assetKey}: {tostring(hasGift)}.`
		end
		return `{player.Name} {if hasGift then "has" else "does not have"} gift {assetKey}.`
	end)

	self._cmdrService:RegisterCommand({
		Name = "list-gifts",
		Description = "Lists a player's persisted gifts.",
		Group = "Gifting",
		Args = {
			{ Type = "player", Name = "player", Description = "Gift owner." },
		},
	}, function(_, player: Player)
		const succeeded, gifts = self:GetGiftsAsync(player):Yield()
		if not succeeded then
			return `Could not list {player.Name}'s gifts: {tostring(gifts)}.`
		end
		const keys = {}
		for key, gift in gifts do
			table.insert(keys, `{key} x{gift.Quantity} ({gift.AssetType}, by {gift.GiftedBy})`)
		end
		table.sort(keys)
		return if #keys > 0 then table.concat(keys, ", ") else `{player.Name} has no gifts.`
	end)
end

--[=[
	Sets the default restriction with one argument, or a per-gifter override with
	`SetPlayerGiftRestriction(player, restriction)`.

	@within GiftingService
	@param playerOrRestriction Player | GiftingRestriction
	@param restriction GiftingRestriction?
]=]
function GiftingService.SetPlayerGiftRestriction(
	self: GiftingService,
	playerOrRestriction: Player | Restriction,
	restriction: Restriction?
): ()
	if typeof(playerOrRestriction) == "Instance" and playerOrRestriction:IsA("Player") then
		assert(GiftingRestrictions:IsValue(restriction), "Bad restriction")
		self._playerRestrictions[playerOrRestriction] = restriction :: Restriction
		return
	end
	assert(restriction == nil, "Pass either a restriction or player and restriction")
	assert(GiftingRestrictions:IsValue(playerOrRestriction), "Bad restriction")
	self._defaultRestriction = playerOrRestriction :: Restriction
end

--[=[
	Gets the effective gifting restriction.

	@within GiftingService
	@param player Player?
	@return GiftingRestriction
]=]
function GiftingService.GetPlayerGiftRestriction(self: GiftingService, player: Player?): Restriction
	assert(player == nil or (typeof(player) == "Instance" and player:IsA("Player")), "Bad player")
	return if player then self._playerRestrictions[player] or self._defaultRestriction else self._defaultRestriction
end

--[=[
	Associates a gift entitlement with the developer product used to charge the
	gifter. Product gifts default to their own product key; pass gifts require a
	mapping because Roblox cannot sell a pass directly to another user.

	@within GiftingService
	@param assetKey string
	@param purchaseProduct number | string
	@param assetType GiftingAssetType?
]=]
function GiftingService.RegisterGiftProduct(
	self: GiftingService,
	assetKey: string,
	purchaseProduct: number | string,
	assetType: AssetType?
): ()
	assert(type(assetKey) == "string" and assetKey ~= "", "Bad assetKey")
	assert(
		type(purchaseProduct) == "number" or (type(purchaseProduct) == "string" and purchaseProduct ~= ""),
		"Bad purchaseProduct"
	)
	assert(assetType == nil or GiftingAssetTypes:IsValue(assetType), "Bad assetType")
	self._giftProductMappings[assetKey] = {
		purchaseProduct = purchaseProduct,
		assetType = assetType,
	}
end

--[=[
	Checks social restrictions and configuration without granting anything.

	@within GiftingService
	@param gifter Player
	@param recipient Player
	@param assetKey string
	@param options GiftOptions?
	@return Promise<boolean, string?>
]=]
function GiftingService.CanGiftAsync(
	self: GiftingService,
	gifter: Player,
	recipient: Player,
	assetKey: string,
	options: GiftOptions?
): Promise.Promise<any>
	assert(typeof(gifter) == "Instance" and gifter:IsA("Player"), "Bad gifter")
	assert(typeof(recipient) == "Instance" and recipient:IsA("Player"), "Bad recipient")
	assert(gifter.Parent == Players, "Gifter is not in this server")
	assert(recipient.Parent == Players, "Recipient is not in this server")
	assert(type(assetKey) == "string" and assetKey ~= "", "Bad assetKey")
	assert(options == nil or type(options) == "table", "Bad options")
	if options then
		assert(options.AssetType == nil or GiftingAssetTypes:IsValue(options.AssetType), "Bad options.AssetType")
		assert(
			options.BypassRestriction == nil or type(options.BypassRestriction) == "boolean",
			"Bad options.BypassRestriction"
		)
		assert(options.AllowSelf == nil or type(options.AllowSelf) == "boolean", "Bad options.AllowSelf")
	end

	return Promise.spawn(function(resolve)
		if gifter == recipient and not (options and options.AllowSelf) then
			resolve(false, "Players cannot gift themselves")
			return
		end
		local assetId = self:_resolveGiftAsset(assetKey, options and options.AssetType)
		if not assetId then
			resolve(false, `No unambiguous configured pass or product exists for {assetKey}`)
			return
		end
		if options and options.BypassRestriction then
			resolve(true)
			return
		end
		if self:GetPlayerGiftRestriction(gifter) == GiftingRestrictions.Friends then
			const succeeded, isFriend = FriendUtils.promiseIsFriendsWith(gifter, recipient.UserId):Yield()
			if not succeeded then
				resolve(false, `Unable to verify friendship: {isFriend}`)
				return
			end
			if not isFriend then
				resolve(false, `{recipient.Name} is not friends with {gifter.Name}`)
				return
			end
		end
		resolve(true)
	end)
end

--[=[
	Grants or updates a persisted gift. The simple two-argument form is a system
	grant; pass an options table for gifter metadata, quantities, duplicate policy,
	custom metadata, receipt idempotency, or restriction overrides.

	@within GiftingService
	@param player Player
	@param assetKey string
	@param options GiftOptions?
	@return Promise<GiftRecord>
]=]
function GiftingService.GiftAsync(
	self: GiftingService,
	player: Player,
	assetKey: string,
	options: GiftOptions?
): Promise.Promise<GiftRecord>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(
		type(assetKey) == "string" and assetKey ~= "" and #assetKey <= GiftingConstants.MAX_GIFT_KEY_LENGTH,
		"Bad assetKey"
	)
	assert(options == nil or type(options) == "table", "Bad options")
	options = options or {}
	assert(options.AssetType == nil or GiftingAssetTypes:IsValue(options.AssetType), "Bad options.AssetType")
	assert(
		options.GiftedBy == nil
			or type(options.GiftedBy) == "number"
			or (typeof(options.GiftedBy) == "Instance" and options.GiftedBy:IsA("Player")),
		"Bad options.GiftedBy"
	)
	assert(
		options.GiftedAt == nil or (type(options.GiftedAt) == "number" and options.GiftedAt >= 0),
		"Bad options.GiftedAt"
	)
	assert(
		options.Quantity == nil
			or (
				type(options.Quantity) == "number"
				and options.Quantity % 1 == 0
				and options.Quantity >= 1
				and options.Quantity <= GiftingConstants.MAX_QUANTITY
			),
		"Bad options.Quantity"
	)
	assert(options.Metadata == nil or type(options.Metadata) == "table", "Bad options.Metadata")
	assert(
		options.DuplicateBehavior == nil or GiftingDuplicateBehavior:IsValue(options.DuplicateBehavior),
		"Bad options.DuplicateBehavior"
	)
	assert(
		options.BypassRestriction == nil or type(options.BypassRestriction) == "boolean",
		"Bad options.BypassRestriction"
	)
	assert(options.AllowSelf == nil or type(options.AllowSelf) == "boolean", "Bad options.AllowSelf")
	assert(
		options.PurchaseId == nil or (type(options.PurchaseId) == "string" and options.PurchaseId ~= ""),
		"Bad options.PurchaseId"
	)

	local assetId, assetType = self:_resolveGiftAsset(assetKey, options.AssetType)
	if not assetId or not assetType then
		return Promise.rejected(`No unambiguous configured pass or product exists for {assetKey}`)
	end

	local giftedBy = 0
	local gifterPlayer: Player? = nil
	if typeof(options.GiftedBy) == "Instance" then
		gifterPlayer = options.GiftedBy :: Player
		giftedBy = gifterPlayer.UserId
	elseif type(options.GiftedBy) == "number" then
		assert(options.GiftedBy >= 0 and options.GiftedBy % 1 == 0, "Bad options.GiftedBy")
		giftedBy = options.GiftedBy
		gifterPlayer = Players:GetPlayerByUserId(giftedBy)
	end
	if
		giftedBy > 0
		and not gifterPlayer
		and not options.BypassRestriction
		and self._defaultRestriction == GiftingRestrictions.Friends
	then
		return Promise.rejected("Friend-restricted gifts require GiftedBy to be an online Player")
	end

	local metadata = TableUtils.deepCopy(options.Metadata or {})
	const metadataEncoded, metadataJson = pcall(HttpService.JSONEncode, HttpService, metadata)
	if not metadataEncoded then
		return Promise.rejected(`Gift metadata is not JSON-safe: {metadataJson}`)
	end
	if #metadataJson > GiftingConstants.MAX_METADATA_JSON_LENGTH then
		return Promise.rejected(`Gift metadata exceeds {GiftingConstants.MAX_METADATA_JSON_LENGTH} encoded bytes`)
	end

	return Promise.spawn(function(resolve, reject)
		if gifterPlayer then
			local canGift, allowed, reason = self:CanGiftAsync(gifterPlayer, player, assetKey, options):Yield()
			if not canGift then
				reject(allowed)
				return
			end
			if not allowed then
				reject(reason)
				return
			end
		end

		local ready, readyError = self:_getReadyPromise(player):Yield()
		if not ready then
			reject(readyError)
			return
		end
		local grantedRecord: GiftRecord? = nil
		const wroteGift, writeError = pcall(function()
			self._playerDataStoreService:SetValue(player, GiftingConstants.ROOT_PATH, function(current)
				const root = self:_normalizeRoot(current)
				if options and options.PurchaseId and root.ProcessedPurchases[options.PurchaseId] then
					grantedRecord = root.Entitlements[assetKey]
					return root
				end

				const quantity = options and options.Quantity or 1
				local behavior = options and options.DuplicateBehavior
				if not behavior then
					behavior = if assetType == GiftingAssetTypes.Product
						then GiftingDuplicateBehavior.Stack
						else GiftingDuplicateBehavior.Keep
				end
				const existing = root.Entitlements[assetKey]
				if existing and behavior == GiftingDuplicateBehavior.Keep then
					grantedRecord = existing
				else
					const newQuantity = if existing and behavior == GiftingDuplicateBehavior.Stack
						then existing.Quantity + quantity
						else quantity
					assert(newQuantity <= GiftingConstants.MAX_QUANTITY, "Gift quantity exceeds maximum")
					grantedRecord = {
						AssetId = assetId,
						AssetType = assetType,
						GiftedBy = giftedBy,
						GiftedAt = math.floor(options and options.GiftedAt or os.time()),
						Quantity = newQuantity,
						Metadata = metadata,
					}
					root.Entitlements[assetKey] = grantedRecord :: GiftRecord
				end
				if options and options.PurchaseId then
					root.ProcessedPurchases[options.PurchaseId] = os.time()
					self:_trimProcessedPurchases(root.ProcessedPurchases)
				end
				return root
			end)
		end)
		if not wroteGift then
			reject(writeError)
			return
		end
		if not grantedRecord then
			reject("Receipt was already processed but its gift record is missing")
			return
		end
		resolve(TableUtils.deepCopy(grantedRecord))
	end)
end

--[=[
	Prompts a player to purchase a gift for another online player. The intent is
	persisted before the prompt. Product gifts use their own product by default;
	pass gifts require RegisterGiftProduct or options.PurchaseProduct.

	@within GiftingService
	@param gifter Player
	@param recipient Player
	@param assetKey string
	@param options PromptGiftOptions?
	@return Promise<boolean>
]=]
function GiftingService.PromptGiftAsync(
	self: GiftingService,
	gifter: Player,
	recipient: Player,
	assetKey: string,
	options: PromptGiftOptions?
): Promise.Promise<boolean>
	assert(typeof(gifter) == "Instance" and gifter:IsA("Player"), "Bad gifter")
	assert(typeof(recipient) == "Instance" and recipient:IsA("Player"), "Bad recipient")
	assert(type(assetKey) == "string" and assetKey ~= "", "Bad assetKey")
	assert(options == nil or type(options) == "table", "Bad options")
	options = options or {}
	assert(options.AssetType == nil or GiftingAssetTypes:IsValue(options.AssetType), "Bad options.AssetType")
	assert(
		options.Quantity == nil
			or (
				type(options.Quantity) == "number"
				and options.Quantity % 1 == 0
				and options.Quantity >= 1
				and options.Quantity <= GiftingConstants.MAX_QUANTITY
			),
		"Bad options.Quantity"
	)
	assert(options.Metadata == nil or type(options.Metadata) == "table", "Bad options.Metadata")
	assert(
		options.DuplicateBehavior == nil or GiftingDuplicateBehavior:IsValue(options.DuplicateBehavior),
		"Bad options.DuplicateBehavior"
	)
	assert(
		options.PurchaseProduct == nil
			or type(options.PurchaseProduct) == "number"
			or (type(options.PurchaseProduct) == "string" and options.PurchaseProduct ~= ""),
		"Bad options.PurchaseProduct"
	)
	assert(options.Timeout == nil or (type(options.Timeout) == "number" and options.Timeout > 0), "Bad options.Timeout")
	if options.Metadata then
		const encoded, metadataJson = pcall(HttpService.JSONEncode, HttpService, options.Metadata)
		assert(encoded, `Gift metadata is not JSON-safe: {metadataJson}`)
		assert(
			#metadataJson <= GiftingConstants.MAX_METADATA_JSON_LENGTH,
			`Gift metadata exceeds {GiftingConstants.MAX_METADATA_JSON_LENGTH} encoded bytes`
		)
	end

	return Promise.spawn(function(resolve, reject)
		local checked, allowed, reason = self:CanGiftAsync(gifter, recipient, assetKey, options):Yield()
		if not checked then
			reject(allowed)
			return
		end
		if not allowed then
			reject(reason)
			return
		end

		const mapping = self._giftProductMappings[assetKey]
		local assetId, assetType =
			self:_resolveGiftAsset(assetKey, options.AssetType or (mapping and mapping.assetType))
		if not assetId or not assetType then
			reject(`No configured gift exists for {assetKey}`)
			return
		end
		const purchaseProduct = options.PurchaseProduct
			or (mapping and mapping.purchaseProduct)
			or (if assetType == GiftingAssetTypes.Product then assetKey else nil)
		if not purchaseProduct then
			reject(`Pass gift {assetKey} needs a developer product mapping via RegisterGiftProduct`)
			return
		end
		const productId =
			self._gameConfigService:GetConfigPicker():ToAssetId(GameConfigAssetTypes.PRODUCT, purchaseProduct)
		if type(productId) ~= "number" or productId <= 0 or productId % 1 ~= 0 then
			reject(`No configured developer product exists for {tostring(purchaseProduct)}`)
			return
		end

		local ready, readyError = self:_getReadyPromise(gifter):Yield()
		if not ready then
			reject(readyError)
			return
		end
		const contextId = HttpService:GenerateGUID(false)
		const pending: PendingPurchase = {
			ContextId = contextId,
			RecipientUserId = recipient.UserId,
			AssetKey = assetKey,
			AssetType = assetType,
			PurchaseProductId = productId,
			CreatedAt = os.time(),
			Quantity = options and options.Quantity or 1,
			DuplicateBehavior = options and options.DuplicateBehavior or (if assetType
					== GiftingAssetTypes.Product
				then GiftingDuplicateBehavior.Stack
				else GiftingDuplicateBehavior.Keep),
			Metadata = TableUtils.deepCopy(options and options.Metadata or {}),
		}
		local conflictingPending: PendingPurchase? = nil
		const wrotePending, pendingError = pcall(function()
			self._playerDataStoreService:SetValue(gifter, GiftingConstants.ROOT_PATH, function(current)
				const root = self:_normalizeRoot(current)
				self:_removeExpiredPendingPurchases(root.PendingPurchases)
				for _, currentPending in root.PendingPurchases do
					if currentPending.PurchaseProductId == productId then
						conflictingPending = currentPending
						return root
					end
				end
				root.PendingPurchases[contextId] = pending
				return root
			end)
		end)
		if not wrotePending then
			reject(pendingError)
			return
		end
		if conflictingPending then
			reject(
				`Developer product {productId} already has an unresolved gift prompt for {conflictingPending.AssetKey}`
			)
			return
		end

		local prompted, purchased = self._gameProductService
			:PromptPurchaseAsync(gifter, GameConfigAssetTypes.PRODUCT, productId, {
				Context = { GiftingContextId = contextId },
				Timeout = options and options.Timeout,
			})
			:Yield()
		if not prompted then
			reject(purchased)
			return
		end
		if not purchased then
			const removed, removeError = pcall(function()
				self:_removePendingPurchase(gifter, contextId)
			end)
			if not removed then
				reject(removeError)
				return
			end
		end
		resolve(purchased)
	end)
end

--[=[
	Returns whether the persisted gift quantity is greater than zero.

	@within GiftingService
	@param player Player
	@param assetKey string
	@return Promise<boolean>
]=]
function GiftingService.HasGiftAsync(self: GiftingService, player: Player, assetKey: string): Promise.Promise<boolean>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(type(assetKey) == "string" and assetKey ~= "", "Bad assetKey")
	return self:_getReadyPromise(player):Then(function(root: GiftRoot)
		const currentRoot = self._giftRoots[player] or root
		const gift = currentRoot.Entitlements[assetKey]
		return gift ~= nil and gift.Quantity > 0
	end)
end

--[=[
	Returns true for either a persisted gift or normal GameProductService ownership.

	@within GiftingService
	@param player Player
	@param assetKey string
	@param assetType GiftingAssetType?
	@return Promise<boolean>
]=]
function GiftingService.HasEntitlementAsync(
	self: GiftingService,
	player: Player,
	assetKey: string,
	assetType: AssetType?
): Promise.Promise<boolean>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(type(assetKey) == "string" and assetKey ~= "", "Bad assetKey")
	local assetId, resolvedType = self:_resolveGiftAsset(assetKey, assetType)
	if not assetId or not resolvedType then
		return Promise.rejected(`No unambiguous configured pass or product exists for {assetKey}`)
	end
	return self:HasGiftAsync(player, assetKey):Then(function(hasGift)
		return if hasGift then true else self._gameProductService:HasAssetAsync(player, resolvedType, assetKey)
	end)
end

--[=[
	Returns a copied gift record.

	@within GiftingService
	@param player Player
	@param assetKey string
	@return Promise<GiftRecord?>
]=]
function GiftingService.GetGiftAsync(
	self: GiftingService,
	player: Player,
	assetKey: string
): Promise.Promise<GiftRecord?>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(type(assetKey) == "string" and assetKey ~= "", "Bad assetKey")
	return self:_getReadyPromise(player):Then(function(root: GiftRoot)
		const currentRoot = self._giftRoots[player] or root
		return TableUtils.deepCopy(currentRoot.Entitlements[assetKey])
	end)
end

--[=[
	Returns a deep copy of all persisted gifts.

	@within GiftingService
	@param player Player
	@return Promise<{ [string]: GiftRecord }>
]=]
function GiftingService.GetGiftsAsync(self: GiftingService, player: Player): Promise.Promise<{ [string]: GiftRecord }>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	return self:_getReadyPromise(player):Then(function(root: GiftRoot)
		const currentRoot = self._giftRoots[player] or root
		return TableUtils.deepCopy(currentRoot.Entitlements)
	end)
end

--[=[
	Removes a gift completely, or decrements it when quantity is provided.

	@within GiftingService
	@param player Player
	@param assetKey string
	@param quantity number?
	@return Promise<boolean>
]=]
function GiftingService.RemoveGiftAsync(
	self: GiftingService,
	player: Player,
	assetKey: string,
	quantity: number?
): Promise.Promise<boolean>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(type(assetKey) == "string" and assetKey ~= "", "Bad assetKey")
	assert(quantity == nil or (type(quantity) == "number" and quantity % 1 == 0 and quantity >= 1), "Bad quantity")
	return self:_getReadyPromise(player):Then(function()
		local removed = false
		const succeeded, errorMessage = pcall(function()
			self._playerDataStoreService:SetValue(player, GiftingConstants.ROOT_PATH, function(current)
				const root = self:_normalizeRoot(current)
				const gift = root.Entitlements[assetKey]
				if not gift then
					return root
				end
				removed = true
				if quantity and gift.Quantity > quantity then
					gift.Quantity -= quantity
				else
					root.Entitlements[assetKey] = nil
				end
				return root
			end)
		end)
		if not succeeded then
			return Promise.rejected(errorMessage)
		end
		return removed
	end)
end

--[=[
	Consumes one or more units of a product gift.

	@within GiftingService
	@param player Player
	@param assetKey string
	@param quantity number?
	@return Promise<boolean>
]=]
function GiftingService.ConsumeGiftAsync(
	self: GiftingService,
	player: Player,
	assetKey: string,
	quantity: number?
): Promise.Promise<boolean>
	return self:RemoveGiftAsync(player, assetKey, quantity or 1)
end

--[=[
	Observes the complete server-side gift map.

	@within GiftingService
	@param player Player
	@return Observable<{ [string]: GiftRecord }>
]=]
function GiftingService.ObserveGifts(
	self: GiftingService,
	player: Player
): Observable.Observable<{ [string]: GiftRecord }>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	return Observable.new(function(sub)
		const maid = Maid.new()
		maid:GivePromise(self:_getReadyPromise(player))
			:Then(function()
				const giftMap = self._giftMaps[player]
				if not giftMap then
					return
				end
				const function update()
					sub:Fire(self:_copyObservableMap(giftMap))
				end
				maid:Add(giftMap.KeyValueChanged:Connect(update))
				update()
			end)
			:Catch(function(errorMessage)
				sub:Fail(errorMessage)
			end)
		return maid
	end)
end

--[=[
	Observes individual gift lifetimes as `(giftKey, giftRecord)` brios.

	@within GiftingService
	@param player Player
	@return Observable<Brio<string, GiftRecord>>
]=]
function GiftingService.ObserveGiftsBrio(self: GiftingService, player: Player): Observable.Observable<any>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	return Observable.new(function(sub)
		const maid = Maid.new()
		maid:GivePromise(self:_getReadyPromise(player))
			:Then(function()
				const giftMap = self._giftMaps[player]
				if not giftMap then
					return
				end
				maid:Add(giftMap
					:ObservePairsBrio()
					:Pipe({
						RxBrioUtils.map(function(key, gift)
							return key, TableUtils.deepCopy(gift)
						end),
					})
					:Subscribe(sub:GetFireFailComplete()))
			end)
			:Catch(function(errorMessage)
				sub:Fail(errorMessage)
			end)
		return maid
	end) :: any
end

function GiftingService._getReadyPromise(self: GiftingService, player: Player): Promise.Promise<GiftRoot>
	const cached = self._readyPromises[player]
	if cached then
		return cached
	end
	const promise = self._maid:GivePromise(self._playerDataStoreService:PromiseProfile(player):Then(function()
		const succeeded, rootOrError = pcall(function()
			local root = self:_normalizeRoot(self._playerDataStoreService:GetValue(player, GiftingConstants.ROOT_PATH))
			self._playerDataStoreService:SetValue(player, GiftingConstants.ROOT_PATH, root)
			root = self:_synchronizePlayer(player, false)
			return root
		end)
		if not succeeded then
			return Promise.rejected(rootOrError)
		end
		return rootOrError
	end))
	self._readyPromises[player] = promise
	promise:Catch(function()
		if self._readyPromises[player] == promise then
			self._readyPromises[player] = nil
		end
	end)
	return promise
end

function GiftingService._normalizeRoot(self: GiftingService, value: any): GiftRoot
	local source = if type(value) == "table" then value else {}
	-- Migrate the earliest direct map shape: Gifted[assetKey] = record.
	if source.Entitlements == nil then
		local direct = {}
		for key, record in source do
			if type(key) == "string" and type(record) == "table" and type(record.AssetId) == "number" then
				direct[key] = record
			end
		end
		source = {
			Entitlements = direct,
			PendingPurchases = {},
			ProcessedPurchases = {},
		}
	end

	const root: GiftRoot = {
		Entitlements = {},
		PendingPurchases = {},
		ProcessedPurchases = {},
	}
	if type(source.Entitlements) == "table" then
		for key, record in source.Entitlements do
			if
				type(key) == "string"
				and key ~= ""
				and #key <= GiftingConstants.MAX_GIFT_KEY_LENGTH
				and type(record) == "table"
				and type(record.AssetId) == "number"
				and record.AssetId > 0
				and record.AssetId % 1 == 0
				and GiftingAssetTypes:IsValue(record.AssetType)
				and type(record.GiftedBy) == "number"
				and record.GiftedBy >= 0
				and type(record.GiftedAt) == "number"
				and type(record.Quantity) == "number"
				and record.Quantity >= 1
			then
				root.Entitlements[key] = {
					AssetId = math.floor(record.AssetId),
					AssetType = record.AssetType,
					GiftedBy = math.floor(record.GiftedBy),
					GiftedAt = math.max(0, math.floor(record.GiftedAt)),
					Quantity = math.min(GiftingConstants.MAX_QUANTITY, math.floor(record.Quantity)),
					Metadata = if type(record.Metadata) == "table" then TableUtils.deepCopy(record.Metadata) else {},
				}
			end
		end
	end
	if type(source.PendingPurchases) == "table" then
		for contextId, pending in source.PendingPurchases do
			if
				type(contextId) == "string"
				and type(pending) == "table"
				and type(pending.RecipientUserId) == "number"
				and type(pending.AssetKey) == "string"
				and GiftingAssetTypes:IsValue(pending.AssetType)
				and type(pending.PurchaseProductId) == "number"
				and type(pending.CreatedAt) == "number"
			then
				root.PendingPurchases[contextId] = TableUtils.deepCopy(pending)
			end
		end
	end
	if type(source.ProcessedPurchases) == "table" then
		for purchaseId, timestamp in source.ProcessedPurchases do
			if type(purchaseId) == "string" and type(timestamp) == "number" then
				root.ProcessedPurchases[purchaseId] = math.max(0, math.floor(timestamp))
			end
		end
	end
	self:_removeExpiredPendingPurchases(root.PendingPurchases)
	self:_trimProcessedPurchases(root.ProcessedPurchases)
	return root
end

function GiftingService._synchronizePlayer(self: GiftingService, player: Player, replicate: boolean): GiftRoot
	const root = self:_normalizeRoot(self._playerDataStoreService:GetValue(player, GiftingConstants.ROOT_PATH))
	self._giftRoots[player] = root
	local giftMap = self._giftMaps[player]
	if not giftMap then
		giftMap = ObservableMap.new()
		self._giftMaps[player] = giftMap
	end
	for key in giftMap do
		if root.Entitlements[key] == nil then
			giftMap:Set(key, nil)
		end
	end
	for key, gift in root.Entitlements do
		if not TableUtils.deepEquivalent(giftMap:Get(key), gift) then
			giftMap:Set(key, TableUtils.deepCopy(gift))
		end
	end
	if replicate then
		const sequence = (self._sequences[player] or 0) + 1
		self._sequences[player] = sequence
		GiftingNetwork.packets.giftsChanged.sendTo(
			GiftingSerializationUtils.serialize(sequence, root.Entitlements),
			player
		)
	end
	return root
end

function GiftingService._copyObservableMap(
	_self: GiftingService,
	giftMap: ObservableMap.ObservableMap<string, GiftRecord>
): { [string]: GiftRecord }
	const gifts = {}
	for key, gift in giftMap do
		gifts[key] = TableUtils.deepCopy(gift)
	end
	return gifts
end

function GiftingService._resolveGiftAsset(
	self: GiftingService,
	assetKey: string,
	preferredType: AssetType?
): (number?, AssetType?)
	const picker = self._gameConfigService:GetConfigPicker()
	if preferredType then
		const asset = picker:FindFirstActiveAssetOfKey(preferredType, assetKey)
		const assetId = asset and asset:GetAssetId()
		return if type(assetId) == "number" then assetId else nil,
			if type(assetId) == "number" then preferredType else nil
	end
	const pass = picker:FindFirstActiveAssetOfKey(GameConfigAssetTypes.PASS, assetKey)
	const product = picker:FindFirstActiveAssetOfKey(GameConfigAssetTypes.PRODUCT, assetKey)
	if pass and product then
		return nil, nil
	end
	const asset = pass or product
	if not asset then
		return nil, nil
	end
	const assetId = asset:GetAssetId()
	if type(assetId) ~= "number" then
		return nil, nil
	end
	return assetId, if pass then GiftingAssetTypes.GamePass else GiftingAssetTypes.Product
end

function GiftingService._processGiftPurchase(self: GiftingService, context: any): any
	if type(context) ~= "table" or context.AssetType ~= GameConfigAssetTypes.PRODUCT then
		return GameProductHandlerResult.SKIP
	end
	const player = context.Player
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return GameProductHandlerResult.RETRY
	end
	local ready, root = self:_getReadyPromise(player):Yield()
	if not ready then
		warn(`[GiftingService] - Unable to load pending gift: {root}`)
		return GameProductHandlerResult.RETRY
	end
	root = self._giftRoots[player] or (root :: GiftRoot)
	local contextId = if type(context.PromptContext) == "table" then context.PromptContext.GiftingContextId else nil
	local pending = if type(contextId) == "string" then root.PendingPurchases[contextId] else nil
	if not pending then
		local oldestCreatedAt = math.huge
		for candidateId, candidate in root.PendingPurchases do
			if candidate.PurchaseProductId == context.AssetId then
				if candidate.CreatedAt < oldestCreatedAt then
					contextId = candidateId
					pending = candidate
					oldestCreatedAt = candidate.CreatedAt
				end
			end
		end
	end
	if not pending or not contextId then
		return GameProductHandlerResult.SKIP
	end
	const recipient = Players:GetPlayerByUserId(pending.RecipientUserId)
	if not recipient then
		return GameProductHandlerResult.RETRY
	end
	const receipt = context.ReceiptInfo
	const purchaseId = if type(receipt) == "table" then tostring(receipt.PurchaseId or "") else ""
	if purchaseId == "" then
		return GameProductHandlerResult.RETRY
	end
	const granted, errorMessage = self:GiftAsync(recipient, pending.AssetKey, {
		AssetType = pending.AssetType,
		GiftedBy = player,
		Quantity = pending.Quantity,
		DuplicateBehavior = pending.DuplicateBehavior,
		Metadata = TableUtils.assign({ PurchaseProductId = pending.PurchaseProductId }, pending.Metadata),
		BypassRestriction = true,
		PurchaseId = purchaseId,
	}):Yield()
	if not granted then
		warn(`[GiftingService] - Paid gift fulfillment failed: {errorMessage}`)
		return GameProductHandlerResult.RETRY
	end
	self:_removePendingPurchase(player, contextId)
	return GameProductHandlerResult.GRANT
end

function GiftingService._removePendingPurchase(self: GiftingService, player: Player, contextId: string): ()
	if not self._playerDataStoreService:GetProfile(player) then
		return
	end
	self._playerDataStoreService:SetValue(player, GiftingConstants.ROOT_PATH, function(current)
		const root = self:_normalizeRoot(current)
		root.PendingPurchases[contextId] = nil
		return root
	end)
end

function GiftingService._removeExpiredPendingPurchases(
	_self: GiftingService,
	pendingPurchases: { [string]: PendingPurchase }
): ()
	const cutoff = os.time() - GiftingConstants.PENDING_PURCHASE_LIFETIME
	for contextId, pending in pendingPurchases do
		if pending.CreatedAt < cutoff then
			pendingPurchases[contextId] = nil
		end
	end
end

function GiftingService._trimProcessedPurchases(_self: GiftingService, processedPurchases: { [string]: number }): ()
	local count = 0
	for _ in processedPurchases do
		count += 1
	end
	while count > GiftingConstants.MAX_PROCESSED_PURCHASES do
		local oldestId = nil
		local oldestTime = math.huge
		for purchaseId, timestamp in processedPurchases do
			if timestamp < oldestTime then
				oldestId = purchaseId
				oldestTime = timestamp
			end
		end
		if not oldestId then
			break
		end
		processedPurchases[oldestId] = nil
		count -= 1
	end
end

function GiftingService.Destroy(self: GiftingService): ()
	self._maid:Destroy()
end

return GiftingService
