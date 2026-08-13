--!strict
--[=[
	Compatibility purchase-data facade used by access and entitlement packages.

	The original Nevermore service reads `PlayerProductManager` binders. This fork already owns prompting,
	receipts, ownership providers, and session purchase state in [GameProductService], so this service keeps
	the upstream API while delegating to the existing product services.

	@class GameProductDataService
]=]

const Players = game:GetService("Players")
const GameProductService = require("../GameProductService")
const GameProductServiceClient = require("../GameProductServiceClient")
const GameProductTypes = require("./GameProductTypes")
const GameProductUtils = require("./GameProductUtils")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const PlayerMock = require("@game/ReplicatedStorage/Packages/PlayerMock")
const Rx = require("@game/ReplicatedStorage/Packages/Rx")
const RxAttributeUtils = require("@game/ReplicatedStorage/Packages/RxAttributeUtils")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const Signal = require("@game/ReplicatedStorage/Packages/Signal")
const TieRealmService = require("@game/ReplicatedStorage/Packages/TieRealmService")
const TieRealms = require("@game/ReplicatedStorage/Packages/TieRealms")
const ValueObject = require("@game/ReplicatedStorage/Packages/ValueObject")
const t = require("@game/ReplicatedStorage/Packages/t")

type AssetType = GameProductTypes.AssetType
type AssetIdOrKey = GameProductTypes.AssetIdOrKey

const SERVER_ONLY_PROMPTING_ATTRIBUTE = "GameProductServerOnlyPrompting"

const GameProductDataService = {}
GameProductDataService.ServiceName = "GameProductDataService"
GameProductDataService.ServerOnlyPromptingAttribute = SERVER_ONLY_PROMPTING_ATTRIBUTE

export type GameProductDataService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_tieRealmService: TieRealmService.TieRealmService,
		_maid: Maid.Maid,
		_serverOnlyPrompting: ValueObject.ValueObject<boolean>,
		_gameProductService: GameProductService.GameProductService?,
		_gameProductServiceClient: GameProductServiceClient.GameProductServiceClient?,

		GamePassPurchased: Signal.Signal<Player, number>,
		ProductPurchased: Signal.Signal<Player, number>,
		AssetPurchased: Signal.Signal<Player, number>,
		BundlePurchased: Signal.Signal<Player, number>,
		MembershipPurchased: Signal.Signal<Player, number>,
		SubscriptionPurchased: Signal.Signal<Player, number>,
	},
	{} :: typeof({ __index = GameProductDataService })
))

local function assertPlayer(player: Player): ()
	assert(t.instanceIsA("Player")(player) or PlayerMock.isMock(player), "Bad player")
end

local function assertAsset(assetType: AssetType, idOrKey: AssetIdOrKey?): ()
	assert(GameProductUtils.isProductAssetType(assetType), "Bad assetType")
	if idOrKey ~= nil then
		assert(t.number(idOrKey) or t.string(idOrKey), "Bad idOrKey")
	end
end

function GameProductDataService.Init(self: GameProductDataService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._tieRealmService = serviceBag:GetService(TieRealmService)
	self._maid = Maid.new()
	self._serverOnlyPrompting = self._maid:Add(ValueObject.new(false, "boolean"))

	self.GamePassPurchased = self._maid:Add(Signal.new() :: any)
	self.ProductPurchased = self._maid:Add(Signal.new() :: any)
	self.AssetPurchased = self._maid:Add(Signal.new() :: any)
	self.BundlePurchased = self._maid:Add(Signal.new() :: any)
	self.MembershipPurchased = self._maid:Add(Signal.new() :: any)
	self.SubscriptionPurchased = self._maid:Add(Signal.new() :: any)

	if self._tieRealmService:GetTieRealm() == TieRealms.CLIENT then
		self._gameProductServiceClient = serviceBag:GetService(GameProductServiceClient)
	else
		self._gameProductService = serviceBag:GetService(GameProductService)
	end
end

function GameProductDataService.Start(self: GameProductDataService): ()
	if self._gameProductService then
		self._maid:GiveTask(self._gameProductService.GamePassPurchased:Connect(function(player, assetId)
			self.GamePassPurchased:Fire(player, assetId)
		end))
		self._maid:GiveTask(self._gameProductService.ProductPurchased:Connect(function(player, assetId)
			self.ProductPurchased:Fire(player, assetId)
		end))

		self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
			player:SetAttribute(SERVER_ONLY_PROMPTING_ATTRIBUTE, self._serverOnlyPrompting.Value)
		end))
		for _, player in Players:GetPlayers() do
			player:SetAttribute(SERVER_ONLY_PROMPTING_ATTRIBUTE, self._serverOnlyPrompting.Value)
		end
	end
end

function GameProductDataService.SetServerOnlyPrompting(self: GameProductDataService, serverOnly: boolean): ()
	assert(t.boolean(serverOnly), "Bad serverOnly")
	assert(self._gameProductService ~= nil, "Server-only prompting can only be configured from the server")

	self._serverOnlyPrompting.Value = serverOnly
	for _, player in Players:GetPlayers() do
		player:SetAttribute(SERVER_ONLY_PROMPTING_ATTRIBUTE, serverOnly)
	end
end

function GameProductDataService.GetServerOnlyPromptingValue(
	self: GameProductDataService
): ValueObject.ValueObject<boolean>
	return self._serverOnlyPrompting
end

function GameProductDataService.ObserveServerOnlyPrompting(
	_self: GameProductDataService,
	player: Player
): Observable.Observable<boolean>
	assertPlayer(player)
	return RxAttributeUtils.observeAttribute(player, SERVER_ONLY_PROMPTING_ATTRIBUTE, false):Pipe({
		Rx.map(function(value: any)
			return value == true
		end) :: any,
		Rx.distinct() :: any,
	}) :: any
end

function GameProductDataService.PromisePromptPurchase(
	self: GameProductDataService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Promise.Promise<boolean>
	assertPlayer(player)
	assertAsset(assetType, idOrKey)
	if self._gameProductService then
		return self._gameProductService:PromptPurchaseAsync(player, assetType, idOrKey)
	end
	assert(self._gameProductServiceClient ~= nil, "Game product service is not initialized")
	assert(player == Players.LocalPlayer, "Client can only prompt LocalPlayer")
	return self._gameProductServiceClient:PromptPurchaseAsync(assetType, idOrKey)
end

function GameProductDataService.PromisePlayerPromptPurchase(
	self: GameProductDataService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Promise.Promise<boolean>
	return self:PromisePromptPurchase(player, assetType, idOrKey)
end

function GameProductDataService.PromisePlayerOwnership(
	self: GameProductDataService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Promise.Promise<boolean>
	assertPlayer(player)
	assertAsset(assetType, idOrKey)
	if self._gameProductService then
		return self._gameProductService:HasAssetAsync(player, assetType, idOrKey)
	end
	assert(self._gameProductServiceClient ~= nil, "Game product service is not initialized")
	assert(player == Players.LocalPlayer, "Client can only query LocalPlayer")
	return self._gameProductServiceClient:HasAssetAsync(assetType, idOrKey)
end

function GameProductDataService.HasPlayerPurchasedThisSession(
	self: GameProductDataService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): boolean
	assertPlayer(player)
	assertAsset(assetType, idOrKey)
	if self._gameProductService then
		return self._gameProductService:HasPlayerPurchasedThisSession(player, assetType, idOrKey)
	end
	assert(self._gameProductServiceClient ~= nil, "Game product service is not initialized")
	assert(player == Players.LocalPlayer, "Client can only query LocalPlayer")
	return self._gameProductServiceClient:GetPurchaseCountThisSession(assetType, idOrKey) > 0
end

function GameProductDataService.PromiseIsOwnable(
	_self: GameProductDataService,
	player: Player,
	assetType: AssetType
): Promise.Promise<boolean>
	assertPlayer(player)
	assertAsset(assetType)
	return Promise.resolved(assetType == "pass")
end

function GameProductDataService.PromisePlayerIsPromptOpen(
	self: GameProductDataService,
	player: Player
): Promise.Promise<boolean>
	assertPlayer(player)
	if self._gameProductService then
		return Promise.resolved(self._gameProductService:IsPromptOpen(player))
	end
	assert(self._gameProductServiceClient ~= nil, "Game product service is not initialized")
	assert(player == Players.LocalPlayer, "Client can only query LocalPlayer")
	return Promise.resolved(self._gameProductServiceClient:IsPromptOpen())
end

function GameProductDataService.PromisePlayerPromptClosed(
	self: GameProductDataService,
	player: Player
): Promise.Promise<boolean>
	return self:PromisePlayerIsPromptOpen(player):Then(function(isOpen)
		return not isOpen
	end)
end

function GameProductDataService.ObservePlayerOwnership(
	self: GameProductDataService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Observable.Observable<boolean>
	return Rx.fromPromise(self:PromisePlayerOwnership(player, assetType, idOrKey)) :: any
end

function GameProductDataService.ObservePlayerAssetPurchased(
	self: GameProductDataService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Observable.Observable<boolean>
	assertPlayer(player)
	assertAsset(assetType, idOrKey)
	if self._gameProductService then
		return self._gameProductService:ObservePlayerPurchase(player, assetType, idOrKey):Pipe({
			Rx.map(function()
				return true
			end) :: any,
		}) :: any
	end
	assert(self._gameProductServiceClient ~= nil, "Game product service is not initialized")
	assert(player == Players.LocalPlayer, "Client can only query LocalPlayer")
	return self._gameProductServiceClient:ObservePurchase(assetType, idOrKey):Pipe({
		Rx.map(function()
			return true
		end) :: any,
	}) :: any
end

function GameProductDataService.ObserveAssetPurchased(
	self: GameProductDataService,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Observable.Observable<Player>
	assertAsset(assetType, idOrKey)
	if self._gameProductService then
		local gameProductService = self._gameProductService
		return Observable.new(function(sub)
			return gameProductService.PurchaseGranted:Connect(
				function(player: Player, purchasedType: AssetType, purchasedId: number)
					local resolvedId = (gameProductService :: any)._resolveAsset(gameProductService, assetType, idOrKey)
					if purchasedType == assetType and purchasedId == resolvedId then
						sub:Fire(player)
					end
				end
			)
		end) :: any
	end

	assert(self._gameProductServiceClient ~= nil, "Game product service is not initialized")
	local gameProductServiceClient = self._gameProductServiceClient
	return Observable.new(function(sub)
		return gameProductServiceClient.PurchaseGranted:Connect(function(purchasedType: AssetType, purchasedId: number)
			local resolvedId = (gameProductServiceClient :: any)._resolveAsset(
				gameProductServiceClient,
				assetType,
				idOrKey
			)
			if purchasedType == assetType and purchasedId == resolvedId then
				sub:Fire(Players.LocalPlayer)
			end
		end)
	end) :: any
end

function GameProductDataService.SetPlayerOwnershipOverride(
	self: GameProductDataService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey,
	ownsAsset: boolean?
): Promise.Promise<()>
	assert(self._gameProductService ~= nil, "Ownership overrides can only be set from the server")
	assertPlayer(player)
	assertAsset(assetType, idOrKey)
	assert(t.boolean(ownsAsset) or ownsAsset == nil, "Bad ownsAsset")
	return Promise.rejected("Ownership overrides require a PlayerProductManager in this fork")
end

function GameProductDataService.ClearPlayerOwnershipOverride(
	self: GameProductDataService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Promise.Promise<()>
	return self:SetPlayerOwnershipOverride(player, assetType, idOrKey, nil)
end

function GameProductDataService.PromisePlayerOwnershipOrPrompt(
	self: GameProductDataService,
	player: Player,
	assetType: AssetType,
	idOrKey: AssetIdOrKey
): Promise.Promise<boolean>
	return self:PromisePlayerOwnership(player, assetType, idOrKey):Then(function(ownsAsset)
		if ownsAsset then
			return true
		end
		return self:PromisePromptPurchase(player, assetType, idOrKey)
	end)
end

function GameProductDataService.Destroy(self: GameProductDataService): ()
	self._maid:DoCleaning()
end

return GameProductDataService
