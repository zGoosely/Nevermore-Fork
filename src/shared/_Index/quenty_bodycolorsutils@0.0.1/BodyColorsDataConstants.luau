--!strict
--[=[
	Defines the stable mappings used to represent Roblox body colors as data.

	@class BodyColorsDataConstants
]=]

const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly({
	ATTRIBUTE_MAPPING = {
		headColor = "HeadColor",
		leftArmColor = "LeftArmColor",
		leftLegColor = "LeftLegColor",
		rightArmColor = "RightArmColor",
		rightLegColor = "RightLegColor",
		torsoColor = "TorsoColor",
	},
	BODY_PART_DATA_KEY_MAPPING = {
		[Enum.BodyPart.Head] = "headColor",
		[Enum.BodyPart.LeftArm] = "leftArmColor",
		[Enum.BodyPart.LeftLeg] = "leftLegColor",
		[Enum.BodyPart.RightArm] = "rightArmColor",
		[Enum.BodyPart.RightLeg] = "rightLegColor",
		[Enum.BodyPart.Torso] = "torsoColor",
	},
})
