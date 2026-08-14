--!strict
--[=[
	Validates, copies, compares, and applies avatar catalog definitions.

	@util AvatarCatalogServiceUtils
]=]

const HumanoidDescriptionUtils = require("@game/ReplicatedStorage/Packages/HumanoidDescriptionUtils")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const t = require("@game/ReplicatedStorage/Packages/t")

const AvatarCatalogServiceTypes = require("./AvatarCatalogServiceTypes")
const WellKnownUnfairPackagesAndParts = require("./Catalog/WellKnownUnfairPackagesAndParts")

type AvatarScales = AvatarCatalogServiceTypes.AvatarScales
type BodyPartCatalog = AvatarCatalogServiceTypes.BodyPartCatalog
type BodyPartDefinition = AvatarCatalogServiceTypes.BodyPartDefinition
type BodyPartReplacementCatalog = AvatarCatalogServiceTypes.BodyPartReplacementCatalog
type PackageCatalog = AvatarCatalogServiceTypes.PackageCatalog
type PackageDefinition = AvatarCatalogServiceTypes.PackageDefinition
type PackageReplacementCatalog = AvatarCatalogServiceTypes.PackageReplacementCatalog

const BODY_PARTS = {
	Enum.BodyPart.Head,
	Enum.BodyPart.Torso,
	Enum.BodyPart.LeftArm,
	Enum.BodyPart.RightArm,
	Enum.BodyPart.LeftLeg,
	Enum.BodyPart.RightLeg,
}

const BODY_PART_PROPERTIES: { [Enum.BodyPart]: string } = {
	[Enum.BodyPart.Head] = "Head",
	[Enum.BodyPart.Torso] = "Torso",
	[Enum.BodyPart.LeftArm] = "LeftArm",
	[Enum.BodyPart.RightArm] = "RightArm",
	[Enum.BodyPart.LeftLeg] = "LeftLeg",
	[Enum.BodyPart.RightLeg] = "RightLeg",
}

const SCALE_PROPERTIES = {
	"BodyTypeScale",
	"DepthScale",
	"HeadScale",
	"HeightScale",
	"ProportionScale",
	"WidthScale",
}

const getReplacementKeyUnchecked = function(
	rigType: Enum.HumanoidRigType,
	bodyPart: Enum.BodyPart,
	sourceAssetId: number
): string
	return `{rigType.Name}:{bodyPart.Name}:{sourceAssetId}`
end

const WELL_KNOWN_UNFAIR_REPLACEMENTS: { [string]: number } = {}
for _, definition in WellKnownUnfairPackagesAndParts.BODY_PARTS do
	for _, assetId in definition.AssetIds do
		const key = getReplacementKeyUnchecked(definition.RigType, definition.BodyPart, assetId)
		WELL_KNOWN_UNFAIR_REPLACEMENTS[key] = definition.ReplacementAssetId
	end
end

const isAssetId = function(value: any): boolean
	return t.numberPositive(value) and value % 1 == 0
end

const isBodyPart = function(value: any): boolean
	return t.enum(Enum.BodyPart)(value) and BODY_PART_PROPERTIES[value] ~= nil
end

const isScale = t.numberMin(0)
const isAvatarScales = t.strictInterface({
	BodyTypeScale = isScale,
	DepthScale = isScale,
	HeadScale = isScale,
	HeightScale = isScale,
	ProportionScale = isScale,
	WidthScale = isScale,
})

const isBodyPartMap = t.map(isBodyPart, isAssetId)
const isBodyPartDefinition = t.strictInterface({
	RigType = t.enum(Enum.HumanoidRigType),
	BodyPart = isBodyPart,
	AssetId = isAssetId,
})
const isPackageDefinition = t.strictInterface({
	RigType = t.enum(Enum.HumanoidRigType),
	BodyParts = isBodyPartMap,
	Scales = t.optional(isAvatarScales),
})

const AvatarCatalogServiceUtils = {}

const getBodyPartDescription = function(description: HumanoidDescription, bodyPart: Enum.BodyPart): BodyPartDescription?
	for _, child in description:GetChildren() do
		if child:IsA("BodyPartDescription") and child.BodyPart == bodyPart then
			return child
		end
	end
	return nil
end

const getBodyPartAssetId = function(description: HumanoidDescription, bodyPart: Enum.BodyPart): number
	const bodyPartDescription = getBodyPartDescription(description, bodyPart)
	if bodyPartDescription then
		return bodyPartDescription.AssetId
	end
	return (description :: any)[BODY_PART_PROPERTIES[bodyPart]]
end

const removeBodyPartDescriptions = function(description: HumanoidDescription, bodyPart: Enum.BodyPart): ()
	for _, child in description:GetChildren() do
		if child:IsA("BodyPartDescription") and child.BodyPart == bodyPart then
			child:Destroy()
		end
	end
end

const setBodyPartAssetId = function(description: HumanoidDescription, bodyPart: Enum.BodyPart, assetId: number): boolean
	const propertyName = BODY_PART_PROPERTIES[bodyPart]
	if propertyName == nil then
		return false
	end
	const bodyPartDescription = getBodyPartDescription(description, bodyPart)
	if bodyPartDescription == nil and (description :: any)[propertyName] == assetId then
		return false
	end
	removeBodyPartDescriptions(description, bodyPart)
	const anyDescription = description :: any
	anyDescription[propertyName] = assetId
	return true
end

--[=[
	Returns whether a value is a valid body-part definition.

	@within AvatarCatalogServiceUtils
	@param value any
	@return boolean
]=]
function AvatarCatalogServiceUtils.isBodyPartDefinition(value: any): boolean
	return isBodyPartDefinition(value)
end

--[=[
	Returns whether a value is a valid avatar-package definition.

	@within AvatarCatalogServiceUtils
	@param value any
	@return boolean
]=]
function AvatarCatalogServiceUtils.isPackageDefinition(value: any): boolean
	return isPackageDefinition(value) and next(value.BodyParts) ~= nil
end

--[=[
	Copies a body-part definition so callers cannot mutate the stored catalog.

	@within AvatarCatalogServiceUtils
	@param definition BodyPartDefinition
	@return BodyPartDefinition
]=]
function AvatarCatalogServiceUtils.copyBodyPart(definition: BodyPartDefinition): BodyPartDefinition
	assert(isBodyPartDefinition(definition), "Bad definition")
	return {
		RigType = definition.RigType,
		BodyPart = definition.BodyPart,
		AssetId = definition.AssetId,
	}
end

--[=[
	Copies an avatar-package definition and its nested maps.

	@within AvatarCatalogServiceUtils
	@param definition PackageDefinition
	@return PackageDefinition
]=]
function AvatarCatalogServiceUtils.copyPackage(definition: PackageDefinition): PackageDefinition
	assert(AvatarCatalogServiceUtils.isPackageDefinition(definition), "Bad definition")

	const bodyParts = table.clone(definition.BodyParts)
	const scales = if definition.Scales then table.clone(definition.Scales) else nil
	return {
		RigType = definition.RigType,
		BodyParts = bodyParts,
		Scales = scales,
	}
end

--[=[
	Creates a package definition from the body assets and scales in a description.

	@within AvatarCatalogServiceUtils
	@param rigType Enum.HumanoidRigType
	@param description HumanoidDescription
	@return PackageDefinition
]=]
function AvatarCatalogServiceUtils.fromDescription(
	rigType: Enum.HumanoidRigType,
	description: HumanoidDescription
): PackageDefinition
	assert(t.enum(Enum.HumanoidRigType)(rigType), "Bad rigType")
	assert(t.instanceIsA("HumanoidDescription")(description), "Bad description")

	const bodyParts: { [Enum.BodyPart]: number } = {}
	for _, bodyPart in BODY_PARTS do
		const assetId = getBodyPartAssetId(description, bodyPart)
		if isAssetId(assetId) then
			bodyParts[bodyPart] = assetId
		end
	end

	local scales: AvatarScales? = nil
	if rigType == Enum.HumanoidRigType.R15 then
		scales = {
			BodyTypeScale = description.BodyTypeScale,
			DepthScale = description.DepthScale,
			HeadScale = description.HeadScale,
			HeightScale = description.HeightScale,
			ProportionScale = description.ProportionScale,
			WidthScale = description.WidthScale,
		}
	end

	return {
		RigType = rigType,
		BodyParts = bodyParts,
		Scales = scales,
	}
end

--[=[
	Returns the body part represented by an avatar asset type, when applicable.

	@within AvatarCatalogServiceUtils
	@param avatarAssetType Enum.AvatarAssetType?
	@return Enum.BodyPart?
]=]
function AvatarCatalogServiceUtils.bodyPartFromAvatarAssetType(avatarAssetType: Enum.AvatarAssetType?): Enum.BodyPart?
	assert(t.optional(t.enum(Enum.AvatarAssetType))(avatarAssetType), "Bad avatarAssetType")
	if avatarAssetType == nil then
		return nil
	end

	const name = avatarAssetType.Name
	if name == "Head" or name == "DynamicHead" then
		return Enum.BodyPart.Head
	end
	for _, bodyPart in BODY_PARTS do
		if bodyPart.Name == name then
			return bodyPart
		end
	end
	return nil
end

--[=[
	Builds the stable lookup key for one automatic body-part replacement.

	@within AvatarCatalogServiceUtils
	@param rigType Enum.HumanoidRigType
	@param bodyPart Enum.BodyPart
	@param sourceAssetId number
	@return string
]=]
function AvatarCatalogServiceUtils.getReplacementKey(
	rigType: Enum.HumanoidRigType,
	bodyPart: Enum.BodyPart,
	sourceAssetId: number
): string
	assert(t.enum(Enum.HumanoidRigType)(rigType), "Bad rigType")
	assert(isBodyPart(bodyPart), "Bad bodyPart")
	assert(isAssetId(sourceAssetId), "Bad sourceAssetId")
	return getReplacementKeyUnchecked(rigType, bodyPart, sourceAssetId)
end

--[=[
	Applies one catalog body part to a description and reports whether it changed.

	@within AvatarCatalogServiceUtils
	@param description HumanoidDescription
	@param definition BodyPartDefinition
	@return boolean
]=]
function AvatarCatalogServiceUtils.applyBodyPart(
	description: HumanoidDescription,
	definition: BodyPartDefinition
): boolean
	assert(t.instanceIsA("HumanoidDescription")(description), "Bad description")
	assert(isBodyPartDefinition(definition), "Bad definition")

	return setBodyPartAssetId(description, definition.BodyPart, definition.AssetId)
end

--[=[
	Replaces body parts in the built-in unfair-avatar list with the rig's default body geometry.

	@within AvatarCatalogServiceUtils
	@param description HumanoidDescription
	@param rigType Enum.HumanoidRigType
	@return boolean
]=]
function AvatarCatalogServiceUtils.applyWellKnownUnfairParts(
	description: HumanoidDescription,
	rigType: Enum.HumanoidRigType
): boolean
	assert(t.instanceIsA("HumanoidDescription")(description), "Bad description")
	assert(t.enum(Enum.HumanoidRigType)(rigType), "Bad rigType")

	local changed = false
	for _, bodyPart in BODY_PARTS do
		const currentAssetId = getBodyPartAssetId(description, bodyPart)
		const key = getReplacementKeyUnchecked(rigType, bodyPart, currentAssetId)
		const replacementAssetId = WELL_KNOWN_UNFAIR_REPLACEMENTS[key]
		if replacementAssetId ~= nil then
			changed = setBodyPartAssetId(description, bodyPart, replacementAssetId) or changed
		end
	end
	return changed
end

--[=[
	Applies all body assets and optional R15 scales from a package definition.

	@within AvatarCatalogServiceUtils
	@param description HumanoidDescription
	@param definition PackageDefinition
	@return boolean
]=]
function AvatarCatalogServiceUtils.applyPackage(
	description: HumanoidDescription,
	definition: PackageDefinition
): boolean
	assert(t.instanceIsA("HumanoidDescription")(description), "Bad description")
	assert(AvatarCatalogServiceUtils.isPackageDefinition(definition), "Bad definition")

	local changed = false
	for bodyPart, assetId in definition.BodyParts do
		changed = AvatarCatalogServiceUtils.applyBodyPart(description, {
			RigType = definition.RigType,
			BodyPart = bodyPart,
			AssetId = assetId,
		}) or changed
	end
	if definition.Scales then
		for _, propertyName in SCALE_PROPERTIES do
			const value = (definition.Scales :: any)[propertyName]
			if (description :: any)[propertyName] ~= value then
				(description :: any)[propertyName] = value
				changed = true
			end
		end
	end
	return changed
end

--[=[
	Returns whether the description currently wears every body part in a package.

	@within AvatarCatalogServiceUtils
	@param description HumanoidDescription
	@param definition PackageDefinition
	@return boolean
]=]
function AvatarCatalogServiceUtils.matchesPackage(
	description: HumanoidDescription,
	definition: PackageDefinition
): boolean
	assert(t.instanceIsA("HumanoidDescription")(description), "Bad description")
	assert(AvatarCatalogServiceUtils.isPackageDefinition(definition), "Bad definition")

	for bodyPart, assetId in definition.BodyParts do
		if BODY_PART_PROPERTIES[bodyPart] == nil or getBodyPartAssetId(description, bodyPart) ~= assetId then
			return false
		end
	end
	return true
end

--[=[
	Applies matching package and body-part replacement rules to a description.

	@within AvatarCatalogServiceUtils
	@param description HumanoidDescription
	@param rigType Enum.HumanoidRigType
	@param packages PackageCatalog
	@param packageReplacements PackageReplacementCatalog
	@param bodyParts BodyPartCatalog
	@param bodyPartReplacements BodyPartReplacementCatalog
	@return boolean
]=]
function AvatarCatalogServiceUtils.applyReplacements(
	description: HumanoidDescription,
	rigType: Enum.HumanoidRigType,
	packages: PackageCatalog,
	packageReplacements: PackageReplacementCatalog,
	bodyParts: BodyPartCatalog,
	bodyPartReplacements: BodyPartReplacementCatalog
): boolean
	assert(t.instanceIsA("HumanoidDescription")(description), "Bad description")
	assert(t.enum(Enum.HumanoidRigType)(rigType), "Bad rigType")
	assert(t.table(packages), "Bad packages")
	assert(t.table(packageReplacements), "Bad packageReplacements")
	assert(t.table(bodyParts), "Bad bodyParts")
	assert(t.table(bodyPartReplacements), "Bad bodyPartReplacements")

	local changed = false
	const sourceNames = {}
	for sourceName in packageReplacements do
		table.insert(sourceNames, sourceName)
	end
	table.sort(sourceNames)
	for _, sourceName in sourceNames do
		const source = packages[sourceName]
		const replacement = packages[packageReplacements[sourceName]]
		if
			source
			and replacement
			and source.RigType == rigType
			and AvatarCatalogServiceUtils.matchesPackage(description, source)
		then
			changed = AvatarCatalogServiceUtils.applyPackage(description, replacement) or changed
			break
		end
	end

	for _, bodyPart in BODY_PARTS do
		const sourceAssetId = getBodyPartAssetId(description, bodyPart)
		if isAssetId(sourceAssetId) then
			const key = AvatarCatalogServiceUtils.getReplacementKey(rigType, bodyPart, sourceAssetId)
			const replacement = bodyParts[bodyPartReplacements[key]]
			if replacement then
				changed = AvatarCatalogServiceUtils.applyBodyPart(description, replacement) or changed
			end
		end
	end
	return changed
end

--[=[
	Reads the current description, applies a mutation, and resets the humanoid only when something changed.

	@within AvatarCatalogServiceUtils
	@param humanoid Humanoid
	@param mutate (HumanoidDescription) -> boolean
	@return Promise<boolean>
]=]
function AvatarCatalogServiceUtils.applyDescriptionMutationAsync(
	humanoid: Humanoid,
	mutate: (HumanoidDescription) -> boolean
): Promise.Promise<boolean>
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")
	assert(t.callback(mutate), "Bad mutate")

	return Promise.spawn(function(resolve, reject)
		local description: HumanoidDescription? = nil
		const ok, err = pcall(function()
			description = humanoid:GetAppliedDescription()
		end)
		if not ok or description == nil then
			reject(err or "Could not read applied HumanoidDescription")
			return
		end
		resolve(description)
	end):Then(function(description: HumanoidDescription)
		if not mutate(description) then
			description:Destroy()
			return false
		end
		return HumanoidDescriptionUtils.promiseApplyDescriptionReset(
			humanoid,
			description,
			Enum.AssetTypeVerification.Default
		)
			:Then(function()
				description:Destroy()
				return true
			end, function(err)
				description:Destroy()
				return Promise.rejected(err)
			end)
	end)
end

return AvatarCatalogServiceUtils
