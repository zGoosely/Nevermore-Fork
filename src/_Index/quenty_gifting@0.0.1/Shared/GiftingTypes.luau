--!strict
--[=[
	Shared GiftingService contracts.

	@types GiftingTypes
]=]

const GiftingTypes = {}

export type GiftingAssetType = "pass" | "product"
export type GiftingRestriction = "all" | "friends"
export type GiftingDuplicateBehavior = "keep" | "replace" | "stack"

export type GiftRecord = {
	AssetId: number,
	AssetType: GiftingAssetType,
	GiftedBy: number,
	GiftedAt: number,
	Quantity: number,
	Metadata: { [string]: any },
}

export type GiftOptions = {
	AssetType: GiftingAssetType?,
	GiftedBy: Player | number?,
	GiftedAt: number?,
	Quantity: number?,
	Metadata: { [string]: any }?,
	DuplicateBehavior: GiftingDuplicateBehavior?,
	BypassRestriction: boolean?,
	AllowSelf: boolean?,
	PurchaseId: string?,
}

export type PromptGiftOptions = GiftOptions & {
	PurchaseProduct: number | string?,
	Timeout: number?,
}

return GiftingTypes
