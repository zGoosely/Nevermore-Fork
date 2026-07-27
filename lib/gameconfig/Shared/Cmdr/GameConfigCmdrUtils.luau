--!strict
--[=[
	Registers Cmdr argument types backed by the active GameConfigPicker.

	@class GameConfigCmdrUtils
]=]

const require = require("../../../Loader").load()

const GameConfigAssetTypes = require("GameConfigAssetTypes")
const GameConfigPicker = require("GameConfigPicker")

const GameConfigCmdrUtils = {}

const ASSET_TYPE_ALIASES = {
	product = "productId",
	products = "productIds",
	gamepass = "passId",
	gamepasses = "passIds",
	place = "placeId",
	places = "placeIds",
}

--[=[
	Registers one Cmdr ID and ID-list type for every game-config asset category.

	@within GameConfigCmdrUtils
	@param cmdr any
	@param configPicker GameConfigPicker
]=]
function GameConfigCmdrUtils.registerAssetTypes(cmdr: any, configPicker: GameConfigPicker.GameConfigPicker): ()
	assert(cmdr, "Bad cmdr")
	assert(configPicker, "Bad configPicker")

	for _, assetType in GameConfigAssetTypes:GetValues() do
		GameConfigCmdrUtils.registerAssetType(cmdr, configPicker, assetType)
	end

	for alias, typeName in ASSET_TYPE_ALIASES do
		cmdr.Registry:RegisterTypeAlias(alias, typeName)
	end

	GameConfigCmdrUtils.registerGiftAssetKeyType(cmdr, configPicker)
end

--[=[
	Registers a Cmdr type for keys shared by configured products and passes.

	@within GameConfigCmdrUtils
	@param cmdr any
	@param configPicker GameConfigPicker
]=]
function GameConfigCmdrUtils.registerGiftAssetKeyType(cmdr: any, configPicker: GameConfigPicker.GameConfigPicker): ()
	const assetTypes = { GameConfigAssetTypes.PRODUCT, GameConfigAssetTypes.PASS }
	const getAssetKeys = function(): { string }
		const assetKeys = {}
		const seenKeys = {}
		for _, assetType in assetTypes do
			for _, asset in configPicker:GetAllActiveAssetsOfType(assetType) do
				const assetKey = asset:GetAssetKey()
				if not seenKeys[assetKey] then
					seenKeys[assetKey] = true
					table.insert(assetKeys, assetKey)
				end
			end
		end
		table.sort(assetKeys)
		return assetKeys
	end

	const assetKeyDefinition = {
		Transform = function(text: string)
			return cmdr.Util.MakeFuzzyFinder(getAssetKeys())(text)
		end,
		Validate = function(values)
			return #values > 0, "No product or pass with that key could be found."
		end,
		Autocomplete = function(values)
			const results = {}
			for _, value in values do
				table.insert(results, tostring(value))
			end
			return results
		end,
		Parse = function(values): string?
			return values[1]
		end,
	}

	cmdr.Registry:RegisterType("giftAssetKey", assetKeyDefinition)
end

--[=[
	Registers the Cmdr ID and ID-list type for one game-config asset category.

	@within GameConfigCmdrUtils
	@param cmdr any
	@param configPicker GameConfigPicker
	@param assetType GameConfigAssetType
]=]
function GameConfigCmdrUtils.registerAssetType(
	cmdr: any,
	configPicker: GameConfigPicker.GameConfigPicker,
	assetType: GameConfigAssetTypes.GameConfigAssetType
): ()
	assert(cmdr, "Bad cmdr")
	assert(configPicker, "Bad configPicker")
	assert(GameConfigAssetTypes:IsValue(assetType), "Bad assetType")

	const assetIdDefinition = {
		Transform = function(text: string)
			const assetKeys = {}
			const seenKeys = {}
			for _, asset in configPicker:GetAllActiveAssetsOfType(assetType) do
				const assetKey = asset:GetAssetKey()
				if not seenKeys[assetKey] then
					seenKeys[assetKey] = true
					table.insert(assetKeys, assetKey)
				end
			end
			table.sort(assetKeys)

			const found = cmdr.Util.MakeFuzzyFinder(assetKeys)(text)
			const numericId = tonumber(text)
			if numericId then
				table.insert(found, 1, numericId)
			end
			return found
		end,
		Validate = function(values)
			return #values > 0, `No {assetType} with that key or ID could be found.`
		end,
		Autocomplete = function(values)
			const results = {}
			for _, value in values do
				table.insert(results, tostring(value))
			end
			return results
		end,
		Parse = function(values): number | string?
			const value = values[1]
			if type(value) == "number" then
				return value
			end

			const asset = configPicker:FindFirstActiveAssetOfKey(assetType, value)
			return if asset then asset:GetAssetId() else nil
		end,
	}

	cmdr.Registry:RegisterType(`{assetType}Id`, assetIdDefinition)
	cmdr.Registry:RegisterType(`{assetType}Ids`, cmdr.Util.MakeListableType(assetIdDefinition))
end

return GameConfigCmdrUtils
