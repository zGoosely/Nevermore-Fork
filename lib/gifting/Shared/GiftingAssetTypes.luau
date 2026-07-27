--!strict
--[=[
	Asset categories that can be persisted as gifts.

	@class GiftingAssetTypes
]=]

const require = require("../../Loader").load()

const Enums = require("Enums")

export type GiftingAssetType = "pass" | "product"

return Enums.new({
	GamePass = "pass" :: "pass",
	Product = "product" :: "product",
	PASS = "pass" :: "pass",
	PRODUCT = "product" :: "product",
})
