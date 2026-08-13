--!strict
--[=[
	Enumerates every asset category understood by GameConfigService.

	@class GameConfigAssetTypes
]=]
const Enums = require("@game/ReplicatedStorage/Packages/Enums")

export type GameConfigAssetType =
	"badge"
	| "product"
	| "pass"
	| "asset"
	| "bundle"
	| "place"
	| "subscription"
	| "membership"

return Enums.new({
	BADGE = "badge" :: "badge",
	PRODUCT = "product" :: "product",
	PASS = "pass" :: "pass",
	ASSET = "asset" :: "asset",
	BUNDLE = "bundle" :: "bundle",
	PLACE = "place" :: "place",
	SUBSCRIPTION = "subscription" :: "subscription",
	MEMBERSHIP = "membership" :: "membership",
})
