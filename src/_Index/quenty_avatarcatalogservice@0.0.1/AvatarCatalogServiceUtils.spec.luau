--!strict
--[=[
	Unit tests for avatar catalog validation, package matching, and replacement transforms.

	@class AvatarCatalogServiceUtils.spec
]=]

const Jest = require("@game/ReplicatedStorage/Packages/Jest")

const AvatarCatalogServiceUtils = require("./AvatarCatalogServiceUtils")
const WellKnownUnfairPackagesAndParts = require("./Catalog/WellKnownUnfairPackagesAndParts")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("AvatarCatalogServiceUtils", function()
	it("replaces a dynamic head description with a catalog head", function()
		const description = Instance.new("HumanoidDescription")
		description.HeadColor = Color3.fromRGB(20, 20, 20)
		const dynamicHead = Instance.new("BodyPartDescription")
		dynamicHead.BodyPart = Enum.BodyPart.Head
		dynamicHead.AssetId = 100
		dynamicHead.Color = Color3.fromRGB(255, 224, 189)
		dynamicHead.Parent = description

		const replacement = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Head,
			AssetId = 200,
		}
		const key = AvatarCatalogServiceUtils.getReplacementKey(Enum.HumanoidRigType.R15, Enum.BodyPart.Head, 100)
		const changed = AvatarCatalogServiceUtils.applyReplacements(
			description,
			Enum.HumanoidRigType.R15,
			{},
			{},
			{ DefaultHead = replacement },
			{ [key] = "DefaultHead" }
		)

		expect(changed).toEqual(true)
		expect(description.Head).toEqual(200)
		expect(description.HeadColor).toEqual(Color3.fromRGB(255, 224, 189))
		expect(description:FindFirstChildOfClass("BodyPartDescription")).toEqual(nil)
		description:Destroy()
	end)

	it("keeps package replacement color behavior unchanged", function()
		const description = Instance.new("HumanoidDescription")
		description.HeadColor = Color3.fromRGB(20, 20, 20)
		const dynamicHead = Instance.new("BodyPartDescription")
		dynamicHead.BodyPart = Enum.BodyPart.Head
		dynamicHead.AssetId = 100
		dynamicHead.Color = Color3.fromRGB(255, 224, 189)
		dynamicHead.Parent = description

		const packages = {
			Disallowed = {
				RigType = Enum.HumanoidRigType.R15,
				BodyParts = {
					[Enum.BodyPart.Head] = 100,
				},
				Scales = nil,
			},
			Default = {
				RigType = Enum.HumanoidRigType.R15,
				BodyParts = {
					[Enum.BodyPart.Head] = 200,
				},
				Scales = nil,
			},
		}
		const changed = AvatarCatalogServiceUtils.applyReplacements(
			description,
			Enum.HumanoidRigType.R15,
			packages,
			{ Disallowed = "Default" },
			{},
			{}
		)

		expect(changed).toEqual(true)
		expect(description.Head).toEqual(200)
		expect(description.HeadColor).toEqual(Color3.fromRGB(20, 20, 20))
		description:Destroy()
	end)

	it("matches and replaces a complete R6 package", function()
		const description = Instance.new("HumanoidDescription")
		description.Head = 101
		description.Torso = 102

		const packages = {
			Disallowed = {
				RigType = Enum.HumanoidRigType.R6,
				BodyParts = {
					[Enum.BodyPart.Head] = 101,
					[Enum.BodyPart.Torso] = 102,
				},
				Scales = nil,
			},
			Default = {
				RigType = Enum.HumanoidRigType.R6,
				BodyParts = {
					[Enum.BodyPart.Head] = 201,
					[Enum.BodyPart.Torso] = 202,
				},
				Scales = nil,
			},
		}
		const changed = AvatarCatalogServiceUtils.applyReplacements(
			description,
			Enum.HumanoidRigType.R6,
			packages,
			{ Disallowed = "Default" },
			{},
			{}
		)

		expect(changed).toEqual(true)
		expect(description.Head).toEqual(201)
		expect(description.Torso).toEqual(202)
		description:Destroy()
	end)

	it("replaces every well-known unfair body part with default geometry", function()
		for _, definition in WellKnownUnfairPackagesAndParts.BODY_PARTS do
			for _, assetId in definition.AssetIds do
				const description = Instance.new("HumanoidDescription")
				const anyDescription = description :: any
				anyDescription[definition.BodyPart.Name] = assetId

				const changed = AvatarCatalogServiceUtils.applyWellKnownUnfairParts(description, definition.RigType)

				expect(changed).toEqual(true)
				expect(anyDescription[definition.BodyPart.Name]).toEqual(definition.ReplacementAssetId)
				description:Destroy()
			end
		end
	end)

	it("only references registered body parts from package metadata", function()
		for _, packageDefinition in WellKnownUnfairPackagesAndParts.PACKAGES do
			for _, bodyPartName in packageDefinition.BodyParts do
				expect(WellKnownUnfairPackagesAndParts.BODY_PARTS[bodyPartName] ~= nil).toEqual(true)
			end
		end
	end)

	it("copies package maps instead of exposing catalog state", function()
		const definition = {
			RigType = Enum.HumanoidRigType.R15,
			BodyParts = {
				[Enum.BodyPart.Head] = 100,
			},
			Scales = {
				BodyTypeScale = 0,
				DepthScale = 1,
				HeadScale = 1,
				HeightScale = 1.05,
				ProportionScale = 0,
				WidthScale = 1,
			},
		}
		const copy = AvatarCatalogServiceUtils.copyPackage(definition)
		copy.BodyParts[Enum.BodyPart.Head] = 200

		expect(definition.BodyParts[Enum.BodyPart.Head]).toEqual(100)
		expect(copy.Scales == definition.Scales).toEqual(false)
	end)
end)
