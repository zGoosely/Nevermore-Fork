--!strict
--[=[
	Shared type contracts for avatar catalog entries and replacement rules.

	@types AvatarCatalogServiceTypes
]=]

export type AvatarScales = {
	BodyTypeScale: number,
	DepthScale: number,
	HeadScale: number,
	HeightScale: number,
	ProportionScale: number,
	WidthScale: number,
}

export type BodyPartDefinition = {
	RigType: Enum.HumanoidRigType,
	BodyPart: Enum.BodyPart,
	AssetId: number,
}

export type PackageDefinition = {
	RigType: Enum.HumanoidRigType,
	BodyParts: { [Enum.BodyPart]: number },
	Scales: AvatarScales?,
}

export type BodyPartCatalog = { [string]: BodyPartDefinition }
export type PackageCatalog = { [string]: PackageDefinition }
export type BodyPartReplacementCatalog = { [string]: string }
export type PackageReplacementCatalog = { [string]: string }

return {}
