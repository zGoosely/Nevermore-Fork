--!strict
--[=[
	Caches Roblox avatar bundle and legacy package lookups for one server.

	@class AvatarCatalogCache
	@server
]=]

const Players = game:GetService("Players")

const AccessoryTypeUtils = require("@game/ReplicatedStorage/Packages/AccessoryTypeUtils")
const AssetServiceUtils = require("@game/ReplicatedStorage/Packages/AssetServiceUtils")
const AvatarEditorUtils = require("@game/ReplicatedStorage/Packages/AvatarEditorUtils")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const MarketplaceServiceCache = require("@game/ReplicatedStorage/Packages/MarketplaceServiceCache")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const t = require("@game/ReplicatedStorage/Packages/t")

const AvatarCatalogServiceTypes = require("../AvatarCatalogServiceTypes")
const AvatarCatalogServiceUtils = require("../AvatarCatalogServiceUtils")

type PackageDefinition = AvatarCatalogServiceTypes.PackageDefinition

type ProductInfo = {
	AssetTypeId: number,
}

const AvatarCatalogCache = {}
AvatarCatalogCache.ClassName = "AvatarCatalogCache"
AvatarCatalogCache.__index = AvatarCatalogCache

export type AvatarCatalogCache = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_marketplaceServiceCache: MarketplaceServiceCache.MarketplaceServiceCache,
		_bundlePromises: { [string]: Promise.Promise<PackageDefinition> },
		_packageAssetPromises: { [string]: Promise.Promise<PackageDefinition> },
	},
	{} :: typeof({ __index = AvatarCatalogCache })
))

function AvatarCatalogCache.new(
	marketplaceServiceCache: MarketplaceServiceCache.MarketplaceServiceCache
): AvatarCatalogCache
	assert(t.table(marketplaceServiceCache), "Bad marketplaceServiceCache")

	const self = setmetatable({}, AvatarCatalogCache) :: AvatarCatalogCache
	self._maid = Maid.new()
	self._marketplaceServiceCache = marketplaceServiceCache
	self._bundlePromises = {}
	self._packageAssetPromises = {}
	return self
end

--[=[
	Returns one shared lookup for a Roblox avatar bundle. Rejected lookups are evicted so they can retry.

	@within AvatarCatalogCache
	@param bundleId number
	@param rigType Enum.HumanoidRigType
	@return Promise<PackageDefinition>
]=]
function AvatarCatalogCache.PromiseBundle(
	self: AvatarCatalogCache,
	bundleId: number,
	rigType: Enum.HumanoidRigType
): Promise.Promise<PackageDefinition>
	assert(t.numberPositive(bundleId) and bundleId % 1 == 0, "Bad bundleId")
	assert(t.enum(Enum.HumanoidRigType)(rigType), "Bad rigType")

	const key = `{rigType.Name}:{bundleId}`
	const cached = self._bundlePromises[key]
	if cached then
		return cached
	end

	local originalDescription: HumanoidDescription? = nil
	local conformedDescription: HumanoidDescription? = nil
	const promise = AssetServiceUtils.promiseBundleDetails(bundleId)
		:Then(function(details: AssetServiceUtils.BundleDetails)
			local outfitId: number? = nil
			for _, item in details.Items do
				if item.Type == "UserOutfit" then
					outfitId = item.Id
					break
				end
			end
			if outfitId == nil then
				return Promise.rejected(`Bundle {bundleId} has no UserOutfit`)
			end

			return Promise.spawn(function(resolve, reject)
				local description: HumanoidDescription? = nil
				const ok, err = pcall(function()
					description = Players:GetHumanoidDescriptionFromOutfitIdAsync(outfitId :: number)
				end)
				if not ok or description == nil then
					reject(err or `Could not load outfit {outfitId}`)
					return
				end
				originalDescription = description
				resolve(description)
			end)
		end)
		:Then(function(description: HumanoidDescription)
			return AvatarEditorUtils.promiseConformToAvatarRules(description)
		end)
		:Then(function(description: HumanoidDescription)
			conformedDescription = description
			const definition = AvatarCatalogServiceUtils.fromDescription(rigType, description)
			if originalDescription and originalDescription ~= conformedDescription then
				originalDescription:Destroy()
			end
			originalDescription = nil
			conformedDescription:Destroy()
			conformedDescription = nil
			return definition
		end)

	self._bundlePromises[key] = promise
	self._maid:GivePromise(promise)
	promise:Catch(function()
		const loadedDescription = originalDescription
		if originalDescription then
			originalDescription:Destroy()
			originalDescription = nil
		end
		if conformedDescription and conformedDescription ~= loadedDescription then
			conformedDescription:Destroy()
		end
		conformedDescription = nil
		if self._bundlePromises[key] == promise then
			self._bundlePromises[key] = nil
		end
	end)
	return promise
end

--[=[
	Returns one shared lookup for a legacy Roblox package asset. Asset metadata uses MarketplaceServiceCache.

	@within AvatarCatalogCache
	@param packageAssetId number
	@param rigType Enum.HumanoidRigType
	@return Promise<PackageDefinition>
]=]
function AvatarCatalogCache.PromisePackageAsset(
	self: AvatarCatalogCache,
	packageAssetId: number,
	rigType: Enum.HumanoidRigType
): Promise.Promise<PackageDefinition>
	assert(t.numberPositive(packageAssetId) and packageAssetId % 1 == 0, "Bad packageAssetId")
	assert(t.enum(Enum.HumanoidRigType)(rigType), "Bad rigType")

	const key = `{rigType.Name}:{packageAssetId}`
	const cached = self._packageAssetPromises[key]
	if cached then
		return cached
	end

	const promise = AssetServiceUtils.promiseAssetIdsForPackage(packageAssetId)
		:Then(function(assetIds: { number })
			const productPromises = table.create(#assetIds)
			for index, assetId in assetIds do
				productPromises[index] = self._marketplaceServiceCache
					:PromiseProductInfo(assetId, Enum.InfoType.Asset)
					:Then(function(productInfo: ProductInfo)
						return {
							assetId = assetId,
							avatarAssetType = AccessoryTypeUtils.convertAssetTypeIdToAvatarAssetType(
								productInfo.AssetTypeId
							),
						}
					end)
			end
			return Promise.all(productPromises)
		end)
		:Then(function(...: { assetId: number, avatarAssetType: Enum.AvatarAssetType? })
			const items = { ... }
			const bodyParts: { [Enum.BodyPart]: number } = {}
			for _, item in items do
				const bodyPart = AvatarCatalogServiceUtils.bodyPartFromAvatarAssetType(item.avatarAssetType)
				if bodyPart then
					bodyParts[bodyPart] = item.assetId
				end
			end
			if next(bodyParts) == nil then
				return Promise.rejected(`Package asset {packageAssetId} contains no avatar body parts`)
			end
			return {
				RigType = rigType,
				BodyParts = bodyParts,
				Scales = nil,
			}
		end)

	self._packageAssetPromises[key] = promise
	self._maid:GivePromise(promise)
	promise:Catch(function()
		if self._packageAssetPromises[key] == promise then
			self._packageAssetPromises[key] = nil
		end
	end)
	return promise
end

function AvatarCatalogCache.Destroy(self: AvatarCatalogCache): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return AvatarCatalogCache
