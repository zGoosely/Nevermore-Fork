--!strict
--[=[
	Shared GameProductService type contracts.

	@types GameProductTypes
]=]

const GameProductTypes = {}

export type AssetType = "pass" | "product"
export type AssetIdOrKey = number | string

export type PromptOptions = {
	Context: { [string]: any }?,
	Timeout: number?,
}

export type PurchaseContext = {
	Player: Player,
	AssetType: AssetType,
	AssetId: number,
	AssetKey: string?,
	PromptContext: { [string]: any }?,
	ReceiptInfo: { [string]: any }?,
}

return GameProductTypes
