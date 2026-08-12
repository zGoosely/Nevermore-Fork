--!strict
--[=[
	Utilities for validating and naming game-config asset types.

	@class GameConfigAssetTypeUtils
]=]

const require = require("../../../../Loader").load()

const GameConfigAssetTypes = require("GameConfigAssetTypes")

const PLURAL_BY_TYPE: { [GameConfigAssetTypes.GameConfigAssetType]: string } = {
	[GameConfigAssetTypes.BADGE] = "badges",
	[GameConfigAssetTypes.PRODUCT] = "products",
	[GameConfigAssetTypes.PASS] = "passes",
	[GameConfigAssetTypes.ASSET] = "assets",
	[GameConfigAssetTypes.BUNDLE] = "bundles",
	[GameConfigAssetTypes.PLACE] = "places",
	[GameConfigAssetTypes.SUBSCRIPTION] = "subscriptions",
	[GameConfigAssetTypes.MEMBERSHIP] = "memberships",
}

for _, assetType in GameConfigAssetTypes:GetValues() do
	assert(PLURAL_BY_TYPE[assetType], `Missing plural name for asset type {tostring(assetType)}`)
end

const GameConfigAssetTypeUtils = {}

--[=[
	Returns whether a value is a supported asset type.

	@param assetType any
	@return boolean
]=]
function GameConfigAssetTypeUtils.isAssetType(assetType: any): boolean
	return GameConfigAssetTypes:IsValue(assetType)
end

--[=[
	Returns the plural folder name used to contain an asset type.

	@param assetType GameConfigAssetType
	@return string
]=]
function GameConfigAssetTypeUtils.getPlural(assetType: GameConfigAssetTypes.GameConfigAssetType): string
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	return PLURAL_BY_TYPE[assetType]
end

return GameConfigAssetTypeUtils
