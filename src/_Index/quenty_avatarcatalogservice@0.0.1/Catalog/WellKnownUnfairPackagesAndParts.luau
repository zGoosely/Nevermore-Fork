--!strict
--[=[
	A conservative list of Roblox-authored packages and body parts that substantially reduce
	a character's visible silhouette. Games can extend their own replacement rules separately.

	@class WellKnownUnfairPackagesAndParts
]=]

const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly({
	BODY_PARTS = {
		GnomskyBrothersHead = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Head,
			AssetIds = {
				4924605743, -- Classic head
				15105910549, -- Dynamic head
			},
			ReplacementAssetId = 0,
		},
		GnomskyBrothersLeftArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftArm,
			AssetIds = { 4924606646 },
			ReplacementAssetId = 0,
		},
		GnomskyBrothersLeftLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftLeg,
			AssetIds = { 4924607176 },
			ReplacementAssetId = 0,
		},
		GnomskyBrothersRightArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightArm,
			AssetIds = { 4924607824 },
			ReplacementAssetId = 0,
		},
		GnomskyBrothersRightLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightLeg,
			AssetIds = { 4924608321 },
			ReplacementAssetId = 0,
		},
		GnomskyBrothersTorso = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Torso,
			AssetIds = { 4924608984 },
			ReplacementAssetId = 0,
		},
		HeadlessHead = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Head,
			AssetIds = {
				134082579, -- Classic Headless Head
				15093053680, -- Dynamic Headless Head
			},
			ReplacementAssetId = 0,
		},
		KorbloxDeathspeakerRightLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightLeg,
			AssetIds = {
				139607718,
			},
			ReplacementAssetId = 0,
		},
		MagmaFiendHead = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Head,
			AssetIds = {
				2608540431, -- Classic head
				12726967427, -- Dynamic head
			},
			ReplacementAssetId = 0,
		},
		MagmaFiendLeftArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftArm,
			AssetIds = { 2608534881 },
			ReplacementAssetId = 0,
		},
		MagmaFiendLeftLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftLeg,
			AssetIds = { 2608536258 },
			ReplacementAssetId = 0,
		},
		MagmaFiendRightArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightArm,
			AssetIds = { 2608537440 },
			ReplacementAssetId = 0,
		},
		MagmaFiendRightLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightLeg,
			AssetIds = { 2608538559 },
			ReplacementAssetId = 0,
		},
		MagmaFiendTorso = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Torso,
			AssetIds = { 2608539495 },
			ReplacementAssetId = 0,
		},
		PiggyHead = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Head,
			AssetIds = { 11775683481 },
			ReplacementAssetId = 0,
		},
		PiggyLeftArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftArm,
			AssetIds = { 11775676733 },
			ReplacementAssetId = 0,
		},
		PiggyLeftLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftLeg,
			AssetIds = { 11775678171 },
			ReplacementAssetId = 0,
		},
		PiggyRightArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightArm,
			AssetIds = { 11775679683 },
			ReplacementAssetId = 0,
		},
		PiggyRightLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightLeg,
			AssetIds = { 11775680970 },
			ReplacementAssetId = 0,
		},
		PiggyTorso = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Torso,
			AssetIds = { 11775682187 },
			ReplacementAssetId = 0,
		},
		SkellyHead = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Head,
			AssetIds = {
				2510276237, -- Classic head
				15057840947, -- Dynamic head
			},
			ReplacementAssetId = 0,
		},
		SkellyLeftArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftArm,
			AssetIds = { 2510260686 },
			ReplacementAssetId = 0,
		},
		SkellyLeftLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftLeg,
			AssetIds = { 2510269155 },
			ReplacementAssetId = 0,
		},
		SkellyRightArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightArm,
			AssetIds = { 2510270282 },
			ReplacementAssetId = 0,
		},
		SkellyRightLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightLeg,
			AssetIds = { 2510271496 },
			ReplacementAssetId = 0,
		},
		SkellyTorso = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Torso,
			AssetIds = { 2510272577 },
			ReplacementAssetId = 0,
		},
	},
	PACKAGES = {
		GnomskyBrothers = {
			BundleId = 652,
			BodyParts = {
				"GnomskyBrothersHead",
				"GnomskyBrothersLeftArm",
				"GnomskyBrothersLeftLeg",
				"GnomskyBrothersRightArm",
				"GnomskyBrothersRightLeg",
				"GnomskyBrothersTorso",
			},
		},
		HeadlessHorseman = {
			BundleId = 201,
			BodyParts = {
				"HeadlessHead",
			},
		},
		KorbloxDeathspeaker = {
			BundleId = 192,
			LegacyPackageAssetId = 139610216,
			BodyParts = {
				"KorbloxDeathspeakerRightLeg",
			},
		},
		MagmaFiend = {
			BundleId = 429,
			BodyParts = {
				"MagmaFiendHead",
				"MagmaFiendLeftArm",
				"MagmaFiendLeftLeg",
				"MagmaFiendRightArm",
				"MagmaFiendRightLeg",
				"MagmaFiendTorso",
			},
		},
		Piggy = {
			BundleId = 998,
			BodyParts = {
				"PiggyHead",
				"PiggyLeftArm",
				"PiggyLeftLeg",
				"PiggyRightArm",
				"PiggyRightLeg",
				"PiggyTorso",
			},
		},
		Skelly = {
			BundleId = 353,
			BodyParts = {
				"SkellyHead",
				"SkellyLeftArm",
				"SkellyLeftLeg",
				"SkellyRightArm",
				"SkellyRightLeg",
				"SkellyTorso",
			},
		},
	},
})
