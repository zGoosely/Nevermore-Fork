--!strict
--[=[
	Provides utilities to query the AvatarEditorService with a promise wrapper.

	@util AvatarEditorUtils
]=]

const AvatarEditorService = game:GetService("AvatarEditorService")
const RunService = game:GetService("RunService")

const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const t = require("@game/ReplicatedStorage/Packages/t")

const AvatarEditorUtils = {}

--[=[
	Holds item details for a bundle
	https://create.roblox.com/docs/reference/engine/classes/AvatarEditorService#GetItemDetails

	@interface AvatarItemBundledItemDetails
	.Owned boolean
	.Id number
	.Name string
	.Type string
	@within AvatarEditorUtils
]=]
export type AvatarItemBundledItemDetails = {
	Owned: boolean,
	Id: number,
	Name: string,
	Type: string,
}

--[=[
	Holds premium pricing detail
	https://create.roblox.com/docs/reference/engine/classes/AvatarEditorService#GetItemDetails
	@interface PremiumPricingItemDetails
	.PremiumDiscountPercentage number
	.PremiumPriceInRobux number
	@within AvatarEditorUtils
]=]
export type PremiumPricingItemDetails = {
	PremiumDiscountPercentage: number,
	PremiumPriceInRobux: number,
}

--[=[
	A table with a variety of information about avatar items and details.
	https://create.roblox.com/docs/reference/engine/classes/AvatarEditorService#GetItemDetails

	@interface AvatarItemDetails
	.IsForRent boolean
	.ExpectedSellerId number
	.Owned boolean
	.IsPurchasable boolean
	.Id number
	.ItemType "Asset" | "Bundle" | string
	.AssetType "Image" | string
	.BundleType "BodyParts" | string
	.Name string
	.Description string
	.ProductId number
	.Genres { string }
	.BundledItems { AvatarItemBundledItemDetails }
	.ItemStatus { string }
	.ItemRestrictions { "ThirteenPlus" }
	.CreatorType "User" | string
	.CreatorTargetId number
	.CreatorName string
	.Price number
	.PremiumPricing PremiumPricingItemDetails
	.LowestPrice number
	.PriceStatus string
	.UnitsAvailableForConsumption number
	.PurchaseCount number
	.FavoriteCount number
	@within AvatarEditorUtils
]=]
export type AvatarItemDetails = {
	IsForRent: boolean,
	ExpectedSellerId: number,
	Owned: boolean,
	IsPurchasable: boolean,
	Id: number,
	ItemType: "Asset" | "Bundle" | string,
	AssetType: "Image" | string,
	BundleType: "BodyParts" | string,
	Name: string,
	Description: string,
	ProductId: number,
	Genres: { string },
	BundledItems: { AvatarItemBundledItemDetails },
	ItemStatus: { string },
	ItemRestrictions: "ThirteenPlus",
	CreatorType: "User" | string,
	CreatorTargetId: number,
	CreatorName: string,
	Price: number,
	PremiumPricing: PremiumPricingItemDetails,
	LowestPrice: number,
	PriceStatus: string,
	UnitsAvailableForConsumption: number,
	PurchaseCount: number,
	FavoriteCount: number,
}

--[=[
	This function returns the item details for the given item.
	It accepts two parameters - the first indicating the ID of the item being retrieved
	and the second indicating its [Enum.ItemType].

	@param itemType AvatarItemType
	@param itemId number
	@return Promise<AvatarItemDetails>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promiseItemDetails(
	itemId: number,
	itemType: Enum.AvatarItemType
): Promise.Promise<AvatarItemDetails>
	assert(t.number(itemId), "Bad itemId")
	assert(t.enum(Enum.AvatarItemType)(itemType), "Bad itemType")

	return Promise.spawn(function(resolve, reject)
		local itemDetails: AvatarItemDetails
		const ok, err = pcall(function()
			itemDetails = AvatarEditorService:GetItemDetails(itemId, itemType)
		end)

		if not ok then
			return reject(err or "[AvatarEditorUtils.promiseItemDetails] - Failed to GetItemDetails")
		end

		if not t.table(itemDetails) then
			return reject("[AvatarEditorUtils.promiseItemDetails] - Bad itemDetails result")
		end

		return resolve(itemDetails)
	end)
end

--[=[
	Gets the item details for a list of items at once. More efficient than [AvatarEditorService.GetItemDetails]
	if you need to get all the item details of a list.

	@param itemIds { number }
	@param itemType AvatarItemType
	@return Promise<{ { AvatarItemDetails } >
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promiseBatchItemDetails(
	itemIds: { number },
	itemType: Enum.AvatarItemType
): Promise.Promise<{ AvatarItemDetails }>
	assert(t.array(t.number)(itemIds), "Bad itemIds")
	assert(t.enum(Enum.AvatarItemType)(itemType), "Bad itemType")

	return Promise.spawn(function(resolve, reject)
		local batchItemDetailsList: { AvatarItemDetails }
		const ok, err = pcall(function()
			batchItemDetailsList = AvatarEditorService:GetBatchItemDetails(itemIds, itemType)
		end)

		if not ok then
			return reject(err or "[AvatarEditorUtils.promiseBatchItemDetails] - Failed to GetBatchItemDetails")
		end

		if not t.array(t.table)(batchItemDetailsList) then
			return reject("[AvatarEditorUtils.promiseBatchItemDetails] - Got bad batchItemDetailsList result")
		end

		return resolve(batchItemDetailsList)
	end)
end

--[=[
	Returns a new HumanoidDescription with the Shirt and Pants properties updated if necessary.
	Returns nil if default clothing was not needed.

	Default clothing is necessary if the HumanoidDescription does not currently have Shirt and
	Pants equipped and the body colors are too similar.

	@param humanoidDescription HumanoidDescription
	@return Promise<HumanoidDescription?>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promiseCheckApplyDefaultClothing(
	humanoidDescription: HumanoidDescription
): Promise.Promise<HumanoidDescription?>
	assert(t.instanceIsA("HumanoidDescription")(humanoidDescription), "Bad humanoidDescription")

	return Promise.spawn(function(resolve, reject)
		local newDescriptionOrNil: HumanoidDescription?
		const ok, err = pcall(function()
			newDescriptionOrNil = AvatarEditorService:CheckApplyDefaultClothing(humanoidDescription)
		end)

		if not ok then
			return reject(
				err or "[AvatarEditorUtils.promiseCheckApplyDefaultClothing] - Failed to CheckApplyDefaultClothing"
			)
		end

		if newDescriptionOrNil == nil then
			return resolve(newDescriptionOrNil)
		end

		if not t.instanceIsA("HumanoidDescription")(newDescriptionOrNil) then
			return reject("[AvatarEditorUtils.promiseCheckApplyDefaultClothing] - Got bad humanoidDescription result")
		end

		return resolve(newDescriptionOrNil)
	end)
end

--[=[
	Probably makes the humanoid description conform to avatar rules.

	@param humanoidDescription HumanoidDescription
	@return Promise<HumanoidDescription>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promiseConformToAvatarRules(
	humanoidDescription: HumanoidDescription
): Promise.Promise<HumanoidDescription>
	assert(t.instanceIsA("HumanoidDescription")(humanoidDescription), "Bad humanoidDescription")

	return Promise.spawn(function(resolve, reject)
		local newDescription: HumanoidDescription
		const ok, err = pcall(function()
			newDescription = AvatarEditorService:ConformToAvatarRules(humanoidDescription)
		end)

		if not ok then
			return reject(
				err or "[AvatarEditorUtils.promiseConformToAvatarRules] - Failed to CheckApplyDefaultClothing"
			)
		end

		if not t.instanceIsA("HumanoidDescription")(newDescription) then
			return reject("[AvatarEditorUtils.promiseConformToAvatarRules] - Got bad humanoidDescription result")
		end

		return resolve(newDescription)
	end)
end

--[=[
	https://create.roblox.com/docs/reference/engine/classes/AvatarEditorService#GetAvatarRules

	@interface AvatarRulesWearableAssetType
	.MaxNumber number
	.Id number
	.Name string
	@within AvatarEditorUtils
]=]
export type AvatarRulesWearableAssetType = {
	MaxNumber: number,
	Id: number,
	Name: string,
}

--[=[
	https://create.roblox.com/docs/reference/engine/classes/AvatarEditorService#GetAvatarRules

	@interface AvatarRulesBodyColor
	.BrickColorId 0
	.NexColor string
	.Name string
	@within AvatarEditorUtils
]=]
export type AvatarRulesBodyColor = {
	BrickColorId: number,
	NexColor: string,
	Name: string,
}

--[=[
	@interface AvatarRuleDefaultClothingAssetLists
	.DefaultShirtAssetIds { number }
	.DefaultPantAssetIds { number }
	@within AvatarEditorUtils
]=]
export type AvatarRuleDefaultClothingAssetLists = {
	DefaultShirtAssetIds: { number },
	DefaultPantAssetIds: { number },
}

--[=[
	https://create.roblox.com/docs/reference/engine/classes/AvatarEditorService#GetAvatarRules

	@interface AvatarRules
	.PlayerAvatarTypes "R6" | "R15" | string
	.Scales table
	.WearableAssetTypes": { AvatarRulesWearableAssetType }
	.BodyColorsPalette": { AvatarRulesBodyColor }
	.BasicBodyColorsPalette": { AvatarRulesBodyColor }
	.MinimumDeltaEBodyColorDifference number
	.ProportionsAndBodyTypeEnabledForUser boolean
	.DefaultClothingAssetLists": AvatarRuleDefaultClothingAssetLists
	.BundlesEnabledForUser boolean
	.EmotesEnabledForUser boolean
	@within AvatarEditorUtils
]=]
export type AvatarRules = {
	PlayerAvatarTypes: "R6" | "R15" | string,
	Scales: { [string]: number },
	WearableAssetTypes: { AvatarRulesWearableAssetType },
	BodyColorsPalette: { AvatarRulesBodyColor },
	BasicBodyColorsPalette: { AvatarRulesBodyColor },
	MinimumDeltaEBodyColorDifference: number,
	ProportionsAndBodyTypeEnabledForUser: boolean,
	DefaultClothingAssetLists: AvatarRuleDefaultClothingAssetLists,
	BundlesEnabledForUser: boolean,
	EmotesEnabledForUser: boolean,
}

--[=[
	Returns the platform Avatar rules for things such as scaling, default shirts and pants, number of wearable assets.

	https://create.roblox.com/docs/reference/engine/classes/AvatarEditorService#GetAvatarRules

	@return Promise<AvatarRules>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promiseAvatarRules(): Promise.Promise<AvatarRules>
	return Promise.spawn(function(resolve, reject)
		local avatarRulesTable: AvatarRules
		const ok, err = pcall(function()
			avatarRulesTable = AvatarEditorService:GetAvatarRules()
		end)

		if not ok then
			return reject(err or "[AvatarEditorUtils.promiseAvatarRules] - Failed to GetAvatarRules")
		end

		if not t.table(avatarRulesTable) then
			return reject("[AvatarEditorUtils.promiseAvatarRules] - Got bad humanoidDescription avatarRulesTable")
		end

		return resolve(avatarRulesTable)
	end)
end

--[=[
	This function returns if the Players.LocalPlayer has favorited the given bundle or asset.

	@param itemId number
	@param itemType AvatarItemType
	@return Promise<boolean>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promiseIsFavorited(itemId: number, itemType: Enum.AvatarItemType): Promise.Promise<boolean>
	assert(t.number(itemId), "Bad itemId")
	assert(t.enum(Enum.AvatarItemType)(itemType), "Bad itemType")

	return Promise.spawn(function(resolve, reject)
		local isFavorited: boolean
		const ok, err = pcall(function()
			isFavorited = AvatarEditorService:GetFavorite(itemId, itemType)
		end)

		if not ok then
			return reject(err or "[AvatarEditorUtils.promiseIsFavorited] - Failed to GetFavorite")
		end

		if not t.boolean(isFavorited) then
			return reject(err, "[AvatarEditorUtils.promiseIsFavorited] - Not a boolean result for isFavorited")
		end

		return resolve(isFavorited)
	end)
end

--[=[
	This function returns if the Players.LocalPlayer has favorited the given bundle or asset.

	@param catalogSearchParams CatalogSearchParams
	@return Promise<CatalogPages>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promiseSearchCatalog(catalogSearchParams: CatalogSearchParams): Promise.Promise<CatalogPages>
	assert(t.typeof("CatalogSearchParams")(catalogSearchParams), "Bad catalogSearchParams")

	return Promise.spawn(function(resolve, reject)
		local catalogPages: CatalogPages
		const ok, err = pcall(function()
			catalogPages = AvatarEditorService:SearchCatalog(catalogSearchParams)
		end)

		if not ok then
			return reject(err or "[AvatarEditorUtils.promiseSearchCatalog] - Failed to GetFavorite")
		end

		if not t.instanceIsA("CatalogPages")(catalogPages) then
			return reject(err, "[AvatarEditorUtils.promiseSearchCatalog] - Not a boolean result for catalogPages")
		end

		return resolve(catalogPages)
	end)
end

--[=[
	Returns an InventoryPages object with information about owned items in the users inventory with the given AvatarAssetTypes.

	@param assetTypes { AvatarAssetType }
	@return Promise<InventoryPages>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promiseInventoryPages(assetTypes: { Enum.AvatarAssetType }): Promise.Promise<InventoryPages>
	assert(t.array(t.enum(Enum.AvatarAssetType))(assetTypes), "Bad assetTypes")

	return Promise.spawn(function(resolve, reject)
		local inventoryPages: InventoryPages
		const ok, err = pcall(function()
			inventoryPages = AvatarEditorService:GetInventory(assetTypes)
		end)

		if not ok then
			return reject(err or "[AvatarEditorUtils.promiseInventoryPages] - Failed to GetInventory")
		end

		if not t.instanceIsA("InventoryPages")(inventoryPages) then
			return reject("[AvatarEditorUtils.promiseInventoryPages] - Bad inventoryPages instance result")
		end

		return resolve(inventoryPages)
	end)
end

--[=[
	This function returns outfit data for the Players.LocalPlayer. This would be used with
	[Players.GetHumanoidDescriptionFromOutfitId] to update the players character to the outfit.
	Access to this would also depend on [AvatarEditorService.PromptAllowInventoryReadAccess]
	being accepted by the user.

	@param outfitSource OutfitSource
	@param outfitType OutfitType
	@return Promise<OutfitPages>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promiseOutfitPages(
	outfitSource: Enum.OutfitSource,
	outfitType: Enum.OutfitType
): Promise.Promise<OutfitPages>
	assert(t.enum(Enum.OutfitSource)(outfitSource), "Bad outfitSource")
	assert(t.enum(Enum.OutfitType)(outfitType), "Bad outfitType")

	return Promise.spawn(function(resolve, reject)
		local outfitPages: OutfitPages
		const ok, err = pcall(function()
			outfitPages = AvatarEditorService:GetOutfits(outfitSource, outfitSource, outfitType)
		end)

		if not ok then
			return reject(err or "[AvatarEditorUtils.promiseOutfitPages] - Failed to GetOutfits")
		end

		if not t.instanceIsA("OutfitPages")(outfitPages) then
			return reject("[AvatarEditorUtils.promiseOutfitPages] - Bad outfitPages instance result")
		end

		return resolve(outfitPages)
	end)
end

--[=[
	This function returns a list of recommendations based on the given AssetType.

	https://create.roblox.com/docs/reference/engine/classes/AvatarEditorService#GetRecommendedAssets

	:::warning
	This API surface currently returns "AvatarEditorService is not yet enabled" when queried outside
	of approved games.
	:::

	@param assetType AvatarAssetType
	@param contextAssetId number? -- Optional. if not provided just gives recommendations in general
	@return Promise<{ number }>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promiseRecommendedAssets(
	assetType: Enum.AvatarAssetType,
	contextAssetId: number?
): Promise.Promise<{ number }>
	assert(t.enum(Enum.AvatarAssetType)(assetType), "Bad assetType")
	assert(t.optional(t.number)(contextAssetId), "Bad contextAssetId")

	contextAssetId = contextAssetId or 0

	return Promise.spawn(function(resolve, reject)
		local result: { number }
		const ok, err = pcall(function()
			result = AvatarEditorService:GetRecommendedAssets(assetType, contextAssetId)
		end)

		if not ok then
			return reject(err or "Failed to GetRecommendedAssets")
		end

		return resolve(result)
	end)
end

--[=[
	This function returns a list of recommended bundles for a given bundle id.

	@param bundleId number
	@return Promise<{ number }>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promiseRecommendedBundles(bundleId: number): Promise.Promise<{ number }>
	assert(t.number(bundleId), "Bad bundleId")

	return Promise.spawn(function(resolve, reject)
		local recommendedBundleIds: { number }
		const ok, err = pcall(function()
			recommendedBundleIds = AvatarEditorService:GetRecommendedBundles(bundleId)
		end)

		if not ok then
			return reject(err or "Failed to GetRecommendedBundles")
		end

		if not t.array(t.number)(recommendedBundleIds) then
			return reject("Bad recommendedBundleIds (not a table)")
		end

		return resolve(recommendedBundleIds)
	end)
end

--[=[
	Prompts the Players.LocalPlayer to allow the developer to read what items the user has in their inventory and other
	avatar editor related information. The prompt needs to be confirmed by the user for the developer to use
	AvatarEditorService:GetInventory(), AvatarEditorService:GetOutfits() and AvatarEditorService:GetFavorite(). Permission
	does not persist between sessions.

	@return Promise<AvatarPromptResult>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promptAllowInventoryReadAccess(): Promise.Promise<()>
	const maid = Maid.new()

	const promise = Promise.new()
	maid:GiveTask(promise)
	promise:Finally(function()
		maid:DoCleaning()
	end)

	maid:GiveTask(AvatarEditorService.PromptAllowInventoryReadAccessCompleted:Connect(function(avatarPromptResult)
		if avatarPromptResult == Enum.AvatarPromptResult.Success then
			promise:Resolve(avatarPromptResult)
		else
			promise:Reject(avatarPromptResult)
		end
	end))

	const ok, err = pcall(function()
		AvatarEditorService:PromptAllowInventoryReadAccess()
	end)

	if not ok then
		promise:Reject(err or "Failed to PromptAllowInventoryReadAccess")
	end

	if not RunService:IsRunning() then
		promise:Resolve()
	end

	return promise
end

--[=[
	Prompts the Players.LocalPlayer to save the given HumanoidDescription as an outfit.

	@param outfit HumanoidDescription
	@param rigType HumanoidRigType
	@return Promise<AvatarPromptResult>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promptCreateOutfit(
	outfit: HumanoidDescription,
	rigType: Enum.HumanoidRigType
): Promise.Promise<Enum.AvatarPromptResult>
	assert(t.instanceIsA("HumanoidDescription")(outfit), "Bad outfit")
	assert(t.enum(Enum.HumanoidRigType)(rigType), "Bad rigType")

	const maid = Maid.new()

	const promise = Promise.new()
	maid:GiveTask(promise)
	promise:Finally(function()
		maid:DoCleaning()
	end)

	maid:GiveTask(AvatarEditorService.PromptCreateOutfitCompleted:Connect(function(avatarPromptResult, failureType)
		if avatarPromptResult == Enum.AvatarPromptResult.Success then
			promise:Resolve(avatarPromptResult)
		else
			promise:Reject(avatarPromptResult, failureType)
		end
	end))

	const ok, err = pcall(function()
		AvatarEditorService:PromptCreateOutfit(outfit, rigType)
	end)

	if not ok then
		promise:Reject(err or "Failed to PromptCreateOutfit")
	end

	return promise
end

--[=[
	Prompts the Players.LocalPlayer to delete the given outfit.

	@param outfitId number
	@return Promise<AvatarPromptResult>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promptDeleteOutfit(outfitId: number): Promise.Promise<Enum.AvatarPromptResult>
	assert(t.number(outfitId), "Bad outfitId")

	const maid = Maid.new()

	const promise = Promise.new()
	maid:GiveTask(promise)
	promise:Finally(function()
		maid:DoCleaning()
	end)

	maid:GiveTask(
		AvatarEditorService.PromptDeleteOutfitCompleted:Connect(function(avatarPromptResult: Enum.AvatarPromptResult)
			if avatarPromptResult == Enum.AvatarPromptResult.Success then
				promise:Resolve(avatarPromptResult)
			else
				promise:Reject(avatarPromptResult)
			end
		end)
	)

	const ok, err = pcall(function()
		AvatarEditorService:PromptDeleteOutfit(outfitId)
	end)

	if not ok then
		promise:Reject(err or "Failed to PromptDeleteOutfit")
	end

	return promise
end

--[=[
	Prompts the Players.LocalPlayer to delete the given outfit.

	@param outfitId number
	@return Promise<AvatarPromptResult>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promptRenameOutfit(outfitId: number): Promise.Promise<Enum.AvatarPromptResult>
	assert(t.number(outfitId), "Bad outfitId")

	const maid = Maid.new()

	const promise = Promise.new()
	maid:GiveTask(promise)
	promise:Finally(function()
		maid:DoCleaning()
	end)

	maid:GiveTask(
		AvatarEditorService.PromptRenameOutfitCompleted:Connect(function(avatarPromptResult: Enum.AvatarPromptResult)
			if avatarPromptResult == Enum.AvatarPromptResult.Success then
				promise:Resolve(avatarPromptResult)
			else
				promise:Reject(avatarPromptResult)
			end
		end)
	)

	const ok, err = pcall(function()
		AvatarEditorService:PromptRenameOutfit(outfitId)
	end)

	if not ok then
		promise:Reject(err or "Failed to PromptRenameOutfit")
	end

	return promise
end

--[=[
	@param humanoidDescription HumanoidDescription
	@param rigType HumanoidRigType
	@return Promise<AvatarPromptResult>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promptSaveAvatar(
	humanoidDescription: HumanoidDescription,
	rigType: Enum.HumanoidRigType
): Promise.Promise<Enum.AvatarPromptResult>
	assert(t.instanceIsA("HumanoidDescription")(humanoidDescription), "Bad humanoidDescription")
	assert(t.enum(Enum.HumanoidRigType)(rigType), "Bad rigType")

	const maid = Maid.new()

	const promise = Promise.new()
	maid:GiveTask(promise)
	promise:Finally(function()
		maid:DoCleaning()
	end)

	maid:GiveTask(
		AvatarEditorService.PromptSaveAvatarCompleted:Connect(function(avatarPromptResult: Enum.AvatarPromptResult)
			if avatarPromptResult == Enum.AvatarPromptResult.Success then
				promise:Resolve(avatarPromptResult)
			else
				promise:Reject(avatarPromptResult)
			end
		end)
	)

	const ok, err = pcall(function()
		AvatarEditorService:PromptSaveAvatar(humanoidDescription, rigType)
	end)

	if not ok then
		promise:Reject(err or "Failed to PromptSaveAvatar")
	end

	return promise
end

--[=[
	This function prompts the Players.LocalPlayer to favorite or unfavorite the given asset or bundle.

	@param itemId number
	@param itemType Enum.AvatarItemType
	@param shouldFavorite boolean
	@return Promise<AvatarPromptResult>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promptSetFavorite(
	itemId: number,
	itemType: Enum.AvatarItemType,
	shouldFavorite: boolean
): Promise.Promise<Enum.AvatarPromptResult>
	assert(t.number(itemId), "Bad itemId")
	assert(t.enum(Enum.AvatarItemType)(itemType), "Bad itemType")
	assert(t.boolean(shouldFavorite), "Bad shouldFavorite")

	const maid = Maid.new()

	const promise = Promise.new()
	maid:GiveTask(promise)
	promise:Finally(function()
		maid:DoCleaning()
	end)

	maid:GiveTask(
		AvatarEditorService.PromptSetFavoriteCompleted:Connect(function(avatarPromptResult: Enum.AvatarPromptResult)
			if avatarPromptResult == Enum.AvatarPromptResult.Success then
				promise:Resolve(avatarPromptResult)
			else
				promise:Reject(avatarPromptResult)
			end
		end)
	)

	const ok, err = pcall(function()
		AvatarEditorService:PromptSetFavorite(itemId, itemType, shouldFavorite)
	end)

	if not ok then
		promise:Reject(err or "Failed to PromptSetFavorite")
	end

	return promise
end

--[=[
	Prompts the Players.LocalPlayer to update the given outfit with the given HumanoidDescription.

	@param outfitId number
	@param updatedOutfit HumanoidDescription
	@param rigType HumanoidRigType
	@return Promise<AvatarPromptResult>
	@within AvatarEditorUtils
]=]
function AvatarEditorUtils.promptUpdateOutfit(
	outfitId: number,
	updatedOutfit: HumanoidDescription,
	rigType: Enum.HumanoidRigType
): Promise.Promise<Enum.AvatarPromptResult>
	assert(t.number(outfitId), "Bad outfitId")
	assert(t.instanceIsA("HumanoidDescription")(updatedOutfit), "Bad updatedOutfit")
	assert(t.enum(Enum.HumanoidRigType)(rigType), "Bad rigType")

	const maid = Maid.new()

	const promise = Promise.new()
	maid:GiveTask(promise)
	promise:Finally(function()
		maid:DoCleaning()
	end)

	maid:GiveTask(
		AvatarEditorService.PromptUpdateOutfitCompleted:Connect(function(avatarPromptResult: Enum.AvatarPromptResult)
			if avatarPromptResult == Enum.AvatarPromptResult.Success then
				promise:Resolve(avatarPromptResult)
			else
				promise:Reject(avatarPromptResult)
			end
		end)
	)

	const ok, err = pcall(function()
		AvatarEditorService:PromptUpdateOutfit(outfitId, updatedOutfit, rigType)
	end)

	if not ok then
		promise:Reject(err or "[AvatarEditorUtils.promptUpdateOutfit] - Failed to PromptUpdateOutfit")
	end

	return promise
end

return AvatarEditorUtils
