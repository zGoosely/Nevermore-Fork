--!strict
--[=[
	Attribute names used by game-config assets.

	@class GameConfigAssetConstants
]=]
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.readonly({
	ASSET_TYPE_ATTRIBUTE = "AssetType",
	ASSET_ID_ATTRIBUTE = "AssetId",
	NAME_TRANSLATION_KEY_ATTRIBUTE = "NameTranslationKey",
	DESCRIPTION_TRANSLATION_KEY_ATTRIBUTE = "DescriptionTranslationKey",
})
