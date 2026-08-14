--!strict
--[=[
	A conservative list of catalog packages and body parts that substantially reduce
	a character's visible silhouette. Games can extend their own replacement rules separately.

	@class WellKnownUnfairPackagesAndParts
]=]

const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly({
	BODY_PARTS = {
		BillyHead = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Head,
			AssetIds = {
				14498289391, -- Billy
				15177652816, -- Billy 1.0
			},
			ReplacementAssetId = 0,
		},
		BillyLeftArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftArm,
			AssetIds = {
				14498289877, -- Billy
				15177652080, -- Billy 1.0
			},
			ReplacementAssetId = 0,
		},
		BillyLeftLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftLeg,
			AssetIds = {
				14498289824, -- Billy
				15177663260, -- Billy 1.0
			},
			ReplacementAssetId = 0,
		},
		BillyRightArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightArm,
			AssetIds = {
				14498289785, -- Billy
				15177649506, -- Billy 1.0
			},
			ReplacementAssetId = 0,
		},
		BillyRightLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightLeg,
			AssetIds = {
				14498289771, -- Billy
				15177665462, -- Billy 1.0
			},
			ReplacementAssetId = 0,
		},
		BillyTorso = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Torso,
			AssetIds = {
				14498289777, -- Billy
				15177665463, -- Billy 1.0
			},
			ReplacementAssetId = 0,
		},
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
		MiniPlushieTinyHead = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Head,
			AssetIds = { 125378629370015 },
			ReplacementAssetId = 0,
		},
		MiniPlushieTinyLeftArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftArm,
			AssetIds = { 100505795772170 },
			ReplacementAssetId = 0,
		},
		MiniPlushieTinyLeftLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftLeg,
			AssetIds = { 80051239734739 },
			ReplacementAssetId = 0,
		},
		MiniPlushieTinyRightArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightArm,
			AssetIds = { 110353866109560 },
			ReplacementAssetId = 0,
		},
		MiniPlushieTinyRightLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightLeg,
			AssetIds = { 88323716288538 },
			ReplacementAssetId = 0,
		},
		MiniPlushieTinyTorso = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Torso,
			AssetIds = { 76164635122422 },
			ReplacementAssetId = 0,
		},
		MiniShortHead = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Head,
			AssetIds = { 93301331583224 },
			ReplacementAssetId = 0,
		},
		MiniShortLeftArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftArm,
			AssetIds = { 117663748665031 },
			ReplacementAssetId = 0,
		},
		MiniShortLeftLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftLeg,
			AssetIds = { 84573805197915 },
			ReplacementAssetId = 0,
		},
		MiniShortRightArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightArm,
			AssetIds = { 76560469465850 },
			ReplacementAssetId = 0,
		},
		MiniShortRightLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightLeg,
			AssetIds = { 107566307931894 },
			ReplacementAssetId = 0,
		},
		MiniShortTorso = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Torso,
			AssetIds = { 87376904839655 },
			ReplacementAssetId = 0,
		},
		MiniTwoHead = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Head,
			AssetIds = { 15273378858 },
			ReplacementAssetId = 0,
		},
		MiniTwoLeftArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftArm,
			AssetIds = { 15273379146 },
			ReplacementAssetId = 0,
		},
		MiniTwoLeftLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.LeftLeg,
			AssetIds = { 15273379144 },
			ReplacementAssetId = 0,
		},
		MiniTwoRightArm = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightArm,
			AssetIds = { 15273379145 },
			ReplacementAssetId = 0,
		},
		MiniTwoRightLeg = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.RightLeg,
			AssetIds = { 15273379160 },
			ReplacementAssetId = 0,
		},
		MiniTwoTorso = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Torso,
			AssetIds = { 15273378599 },
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
		TinyDynamicHeads = {
			RigType = Enum.HumanoidRigType.R15,
			BodyPart = Enum.BodyPart.Head,
			AssetIds = {
				14525302443, -- Tiny Head! - Dynamic Head
				131807154518854, -- Tiny Head - Dynamic Head
			},
			ReplacementAssetId = 0,
		},
	},
	PACKAGES = {
		Billy = {
			BundleId = 2043,
			BodyParts = {
				"BillyHead",
				"BillyLeftArm",
				"BillyLeftLeg",
				"BillyRightArm",
				"BillyRightLeg",
				"BillyTorso",
			},
		},
		BillyOne = {
			BundleId = 104350,
			BodyParts = {
				"BillyHead",
				"BillyLeftArm",
				"BillyLeftLeg",
				"BillyRightArm",
				"BillyRightLeg",
				"BillyTorso",
			},
		},
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
		MiniPlushieTiny = {
			BundleId = 161986395866906,
			BodyParts = {
				"MiniPlushieTinyHead",
				"MiniPlushieTinyLeftArm",
				"MiniPlushieTinyLeftLeg",
				"MiniPlushieTinyRightArm",
				"MiniPlushieTinyRightLeg",
				"MiniPlushieTinyTorso",
			},
		},
		MiniShort = {
			BundleId = 1459995,
			BodyParts = {
				"MiniShortHead",
				"MiniShortLeftArm",
				"MiniShortLeftLeg",
				"MiniShortRightArm",
				"MiniShortRightLeg",
				"MiniShortTorso",
			},
		},
		MiniTwo = {
			BundleId = 140395,
			BodyParts = {
				"MiniTwoHead",
				"MiniTwoLeftArm",
				"MiniTwoLeftLeg",
				"MiniTwoRightArm",
				"MiniTwoRightLeg",
				"MiniTwoTorso",
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
