--!strict
--[=[
	Creates game-config assets and resolves their Roblox cloud metadata.

	@class GameConfigAssetUtils
]=]

const require = require("../../../../Loader").load()

const AttributeUtils = require("AttributeUtils")
const BadgeUtils = require("BadgeUtils")
const Binder = require("Binder")
const GameConfigAssetConstants = require("GameConfigAssetConstants")
const GameConfigAssetTypes = require("GameConfigAssetTypes")
const MarketplaceServiceCache = require("MarketplaceServiceCache")
const Promise = require("Promise")
const ServiceBag = require("ServiceBag")

export type GameConfigAssetId = number | string

const GameConfigAssetUtils = {}

--[=[
	Returns whether an identifier has the correct representation for an asset type.
	Subscriptions and memberships use string identifiers; the remaining Roblox
	asset categories use positive integer IDs.

	@param assetType GameConfigAssetType
	@param assetId any
	@return boolean
]=]
function GameConfigAssetUtils.isValidAssetId(assetType: GameConfigAssetTypes.GameConfigAssetType, assetId: any): boolean
	if assetType == GameConfigAssetTypes.SUBSCRIPTION or assetType == GameConfigAssetTypes.MEMBERSHIP then
		return type(assetId) == "string" and assetId ~= ""
	end

	return type(assetId) == "number" and assetId > 0 and assetId % 1 == 0
end

--[=[
	Creates and binds a replicated Folder representing one configured asset.

	@param binder Binder<GameConfigAssetBase>
	@param assetType GameConfigAssetType
	@param assetKey string
	@param assetId GameConfigAssetId
	@return Folder
]=]
function GameConfigAssetUtils.create(
	binder: Binder.Binder<any>,
	assetType: GameConfigAssetTypes.GameConfigAssetType,
	assetKey: string,
	assetId: GameConfigAssetId
): Folder
	assert(Binder.isBinder(binder), "Bad binder")
	assert(GameConfigAssetTypes:IsValue(assetType), "Bad assetType")
	assert(type(assetKey) == "string" and assetKey ~= "", "Bad assetKey")
	assert(GameConfigAssetUtils.isValidAssetId(assetType, assetId), "Bad assetId")

	const asset = Instance.new("Folder")
	asset.Name = assetKey
	AttributeUtils.initAttribute(asset, GameConfigAssetConstants.ASSET_TYPE_ATTRIBUTE, assetType)
	AttributeUtils.initAttribute(asset, GameConfigAssetConstants.ASSET_ID_ATTRIBUTE, assetId)
	binder:Bind(asset)

	return asset
end

--[=[
	Retrieves Roblox cloud metadata for a numeric configured asset. Subscription
	and membership metadata are not exposed through GetProductInfoAsync and resolve
	to nil.

	@param serviceBag ServiceBag
	@param assetType GameConfigAssetType
	@param assetId GameConfigAssetId
	@return Promise<any>
]=]
function GameConfigAssetUtils.promiseCloudDataForAssetType(
	serviceBag: ServiceBag.ServiceBag,
	assetType: GameConfigAssetTypes.GameConfigAssetType,
	assetId: GameConfigAssetId
): Promise.Promise<any>
	assert(serviceBag, "No serviceBag")
	assert(GameConfigAssetTypes:IsValue(assetType), "Bad assetType")
	assert(GameConfigAssetUtils.isValidAssetId(assetType, assetId), "Bad assetId")

	if assetType == GameConfigAssetTypes.SUBSCRIPTION then
		const marketplaceCache = serviceBag:GetService(MarketplaceServiceCache)
		return marketplaceCache:PromiseSubscriptionProductInfo(assetId :: string)
	elseif assetType == GameConfigAssetTypes.MEMBERSHIP then
		return Promise.resolved(nil)
	elseif assetType == GameConfigAssetTypes.BADGE then
		return BadgeUtils.promiseBadgeInfo(assetId :: number)
	end

	assert(type(assetId) == "number", "Numeric asset type has a non-numeric assetId")
	const marketplaceCache = serviceBag:GetService(MarketplaceServiceCache)
	if assetType == GameConfigAssetTypes.PRODUCT then
		return marketplaceCache:PromiseProductInfo(assetId, Enum.InfoType.Product)
	elseif assetType == GameConfigAssetTypes.PASS then
		return marketplaceCache:PromiseProductInfo(assetId, Enum.InfoType.GamePass)
	elseif assetType == GameConfigAssetTypes.PLACE or assetType == GameConfigAssetTypes.ASSET then
		return marketplaceCache:PromiseProductInfo(assetId, Enum.InfoType.Asset)
	elseif assetType == GameConfigAssetTypes.BUNDLE then
		return marketplaceCache:PromiseProductInfo(assetId, Enum.InfoType.Bundle)
	end

	return Promise.resolved(nil)
end

return GameConfigAssetUtils
