--!strict
--[=[
	Asset categories that can be persisted as gifts.

	@class GiftingAssetTypes
]=]
const Enums = require("@game/ReplicatedStorage/Packages/Enums")

export type GiftingAssetType = "pass" | "product"

return Enums.new({
	GamePass = "pass" :: "pass",
	Product = "product" :: "product",
	PASS = "pass" :: "pass",
	PRODUCT = "product" :: "product",
})
