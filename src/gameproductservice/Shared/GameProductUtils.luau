--!strict
--[=[
	Shared helpers for the two GameProductService asset categories.

	@util GameProductUtils
]=]

const require = require("../../Loader").load()

const GameConfigAssetTypes = require("GameConfigAssetTypes")

const GameProductUtils = {}

local PASS_CODE = 0
local PRODUCT_CODE = 1

--[=[
	Returns whether a value is one of the product asset types supported by
	GameProductService.

	@within GameProductUtils
	@param assetType any
	@return boolean
]=]
function GameProductUtils.isProductAssetType(assetType: any): boolean
	return assetType == GameConfigAssetTypes.PASS or assetType == GameConfigAssetTypes.PRODUCT
end

--[=[
	Converts a product asset type to its compact network code.

	@within GameProductUtils
	@param assetType "pass" | "product"
	@return number
]=]
function GameProductUtils.assetTypeToCode(assetType: "pass" | "product"): number
	assert(GameProductUtils.isProductAssetType(assetType), "Bad assetType")
	return if assetType == GameConfigAssetTypes.PASS then PASS_CODE else PRODUCT_CODE
end

--[=[
	Converts a compact network code back to a product asset type.

	@within GameProductUtils
	@param code number
	@return ("pass" | "product")?
]=]
function GameProductUtils.codeToAssetType(code: number): "pass" | "product"?
	if code == PASS_CODE then
		return GameConfigAssetTypes.PASS
	elseif code == PRODUCT_CODE then
		return GameConfigAssetTypes.PRODUCT
	end
	return nil
end

return GameProductUtils
