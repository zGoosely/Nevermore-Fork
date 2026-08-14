--!strict
--[=[
	Utility methods for converting Roblox avatar and accessory asset types.

	@util AccessoryTypeUtils
]=]

const AvatarEditorService = game:GetService("AvatarEditorService")

const EnumUtils = require("@game/ReplicatedStorage/Packages/EnumUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

const isAvatarAssetType = t.enum(Enum.AvatarAssetType)

const AccessoryTypeUtils = {}

--[=[
	Attempts to convert an avatar asset type into its corresponding accessory type.

	@within AccessoryTypeUtils
	@param avatarAssetType Enum.AvatarAssetType
	@return Enum.AccessoryType?
	@return string?
]=]
function AccessoryTypeUtils.tryGetAccessoryType(avatarAssetType: Enum.AvatarAssetType?): (Enum.AccessoryType?, string?)
	if avatarAssetType == nil then
		return nil, "No avatarAssetType"
	end

	if not isAvatarAssetType(avatarAssetType) then
		return nil, "Bad avatarAssetType"
	end

	local accessoryType: Enum.AccessoryType?
	const ok, err = pcall(function()
		accessoryType = AvatarEditorService:GetAccessoryType(avatarAssetType)
	end)
	if not ok then
		return nil, tostring(err or "Failed to GetAccessoryType from avatarAssetType")
	end

	return accessoryType
end

--[=[
	Converts an accessory type name into an enum value, or `Unknown` when no matching value exists.

	@within AccessoryTypeUtils
	@param accessoryType string
	@return Enum.AccessoryType
]=]
function AccessoryTypeUtils.getAccessoryTypeFromName(accessoryType: string): Enum.AccessoryType
	assert(t.string(accessoryType), "Bad accessoryType")

	for _, enumItem in Enum.AccessoryType:GetEnumItems() do
		if enumItem.Name == accessoryType then
			return enumItem
		end
	end

	return Enum.AccessoryType.Unknown
end

--[=[
	Converts a numeric asset type identifier into an `Enum.AssetType` value when recognized.

	@within AccessoryTypeUtils
	@param assetTypeId number
	@return Enum.AssetType?
]=]
function AccessoryTypeUtils.convertAssetTypeIdToAssetType(assetTypeId: number): Enum.AssetType?
	assert(t.number(assetTypeId), "Bad assetTypeId")

	return EnumUtils.toEnum(Enum.AssetType, assetTypeId) :: Enum.AssetType?
end

--[=[
	Converts a numeric avatar asset type identifier into an `Enum.AvatarAssetType` value when recognized.

	@within AccessoryTypeUtils
	@param avatarAssetTypeId number
	@return Enum.AvatarAssetType?
]=]
function AccessoryTypeUtils.convertAssetTypeIdToAvatarAssetType(avatarAssetTypeId: number): Enum.AvatarAssetType?
	assert(t.number(avatarAssetTypeId), "Bad avatarAssetTypeId")

	return EnumUtils.toEnum(Enum.AvatarAssetType, avatarAssetTypeId) :: Enum.AvatarAssetType?
end

return AccessoryTypeUtils
