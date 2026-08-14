--!strict
--[=[
	Transfers, validates, serializes, and applies body-color data.

	@util BodyColorsDataUtils
]=]

const Color3SerializationUtils = require("@game/ReplicatedStorage/Packages/Color3SerializationUtils")
const Color3Utils = require("@game/ReplicatedStorage/Packages/Color3Utils")
const t = require("@game/ReplicatedStorage/Packages/t")

const BodyColorsDataConstants = require("./BodyColorsDataConstants")

export type BodyColorsData = {
	headColor: Color3?,
	leftArmColor: Color3?,
	leftLegColor: Color3?,
	rightArmColor: Color3?,
	rightLegColor: Color3?,
	torsoColor: Color3?,
}

export type DataStoreSafeBodyColorsData = {
	headColor: Color3SerializationUtils.SerializedColor3?,
	leftArmColor: Color3SerializationUtils.SerializedColor3?,
	leftLegColor: Color3SerializationUtils.SerializedColor3?,
	rightArmColor: Color3SerializationUtils.SerializedColor3?,
	rightLegColor: Color3SerializationUtils.SerializedColor3?,
	torsoColor: Color3SerializationUtils.SerializedColor3?,
}

const isBodyColorsData = t.strictInterface({
	headColor = t.optional(t.Color3),
	leftArmColor = t.optional(t.Color3),
	leftLegColor = t.optional(t.Color3),
	rightArmColor = t.optional(t.Color3),
	rightLegColor = t.optional(t.Color3),
	torsoColor = t.optional(t.Color3),
})

const isSerializedColor3 = Color3SerializationUtils.isSerializedColor3
const isDataStoreSafeBodyColorsData = t.strictInterface({
	headColor = t.optional(isSerializedColor3),
	leftArmColor = t.optional(isSerializedColor3),
	leftLegColor = t.optional(isSerializedColor3),
	rightArmColor = t.optional(isSerializedColor3),
	rightLegColor = t.optional(isSerializedColor3),
	torsoColor = t.optional(isSerializedColor3),
})

const BodyColorsDataUtils = {}

--[=[
	Validates and returns body-color data.

	@within BodyColorsDataUtils
	@param bodyColorsData BodyColorsData
	@return BodyColorsData
]=]
function BodyColorsDataUtils.createBodyColorsData(bodyColorsData: BodyColorsData): BodyColorsData
	assert(isBodyColorsData(bodyColorsData), "Bad bodyColorsData")
	return bodyColorsData
end

--[=[
	Returns whether a value is valid body-color data.

	@within BodyColorsDataUtils
	@param value any
	@return boolean
]=]
function BodyColorsDataUtils.isBodyColorsData(value: any): boolean
	return isBodyColorsData(value)
end

--[=[
	Creates body-color data with one color for every body part.

	@within BodyColorsDataUtils
	@param color3 Color3
	@return BodyColorsData
]=]
function BodyColorsDataUtils.fromUniformColor(color3: Color3): BodyColorsData
	assert(t.Color3(color3), "Bad color3")
	return {
		headColor = color3,
		leftArmColor = color3,
		leftLegColor = color3,
		rightArmColor = color3,
		rightLegColor = color3,
		torsoColor = color3,
	}
end

--[=[
	Creates body-color data from a BodyColors instance.

	@within BodyColorsDataUtils
	@param bodyColors BodyColors
	@return BodyColorsData
]=]
function BodyColorsDataUtils.fromBodyColors(bodyColors: BodyColors): BodyColorsData
	assert(t.instanceIsA("BodyColors")(bodyColors), "Bad bodyColors")
	return {
		headColor = bodyColors.HeadColor3,
		leftArmColor = bodyColors.LeftArmColor3,
		leftLegColor = bodyColors.LeftLegColor3,
		rightArmColor = bodyColors.RightArmColor3,
		rightLegColor = bodyColors.RightLegColor3,
		torsoColor = bodyColors.TorsoColor3,
	}
end

--[=[
	Returns whether a value is DataStore-safe serialized body-color data.

	@within BodyColorsDataUtils
	@param value any
	@return boolean
]=]
function BodyColorsDataUtils.isDataStoreSafeBodyColorsData(value: any): boolean
	return isDataStoreSafeBodyColorsData(value)
end

--[=[
	Serializes body-color data into a DataStore-safe representation.

	@within BodyColorsDataUtils
	@param bodyColorsData BodyColorsData
	@return DataStoreSafeBodyColorsData
]=]
function BodyColorsDataUtils.toDataStoreSafeBodyColorsData(bodyColorsData: BodyColorsData): DataStoreSafeBodyColorsData
	assert(isBodyColorsData(bodyColorsData), "Bad bodyColorsData")
	return {
		headColor = if bodyColorsData.headColor
			then Color3SerializationUtils.serialize(bodyColorsData.headColor)
			else nil,
		leftArmColor = if bodyColorsData.leftArmColor
			then Color3SerializationUtils.serialize(bodyColorsData.leftArmColor)
			else nil,
		leftLegColor = if bodyColorsData.leftLegColor
			then Color3SerializationUtils.serialize(bodyColorsData.leftLegColor)
			else nil,
		rightArmColor = if bodyColorsData.rightArmColor
			then Color3SerializationUtils.serialize(bodyColorsData.rightArmColor)
			else nil,
		rightLegColor = if bodyColorsData.rightLegColor
			then Color3SerializationUtils.serialize(bodyColorsData.rightLegColor)
			else nil,
		torsoColor = if bodyColorsData.torsoColor
			then Color3SerializationUtils.serialize(bodyColorsData.torsoColor)
			else nil,
	}
end

--[=[
	Deserializes DataStore-safe body-color data.

	@within BodyColorsDataUtils
	@param data DataStoreSafeBodyColorsData
	@return BodyColorsData
]=]
function BodyColorsDataUtils.fromDataStoreSafeBodyColorsData(data: DataStoreSafeBodyColorsData): BodyColorsData
	assert(isDataStoreSafeBodyColorsData(data), "Bad data")
	return {
		headColor = if data.headColor then Color3SerializationUtils.deserialize(data.headColor) else nil,
		leftArmColor = if data.leftArmColor then Color3SerializationUtils.deserialize(data.leftArmColor) else nil,
		leftLegColor = if data.leftLegColor then Color3SerializationUtils.deserialize(data.leftLegColor) else nil,
		rightArmColor = if data.rightArmColor then Color3SerializationUtils.deserialize(data.rightArmColor) else nil,
		rightLegColor = if data.rightLegColor then Color3SerializationUtils.deserialize(data.rightLegColor) else nil,
		torsoColor = if data.torsoColor then Color3SerializationUtils.deserialize(data.torsoColor) else nil,
	}
end

--[=[
	Reads effective body colors from a HumanoidDescription. BodyPartDescription colors override legacy color fields.

	@within BodyColorsDataUtils
	@param humanoidDescription HumanoidDescription
	@return BodyColorsData
]=]
function BodyColorsDataUtils.fromHumanoidDescription(humanoidDescription: HumanoidDescription): BodyColorsData
	assert(t.instanceIsA("HumanoidDescription")(humanoidDescription), "Bad humanoidDescription")

	const bodyColorsData: BodyColorsData = {
		headColor = humanoidDescription.HeadColor,
		leftArmColor = humanoidDescription.LeftArmColor,
		leftLegColor = humanoidDescription.LeftLegColor,
		rightArmColor = humanoidDescription.RightArmColor,
		rightLegColor = humanoidDescription.RightLegColor,
		torsoColor = humanoidDescription.TorsoColor,
	}
	const foundBodyParts: { [Enum.BodyPart]: boolean } = {}
	for _, child in humanoidDescription:GetChildren() do
		if child:IsA("BodyPartDescription") and not foundBodyParts[child.BodyPart] then
			const dataKey = BodyColorsDataConstants.BODY_PART_DATA_KEY_MAPPING[child.BodyPart]
			if dataKey then
				(bodyColorsData :: any)[dataKey] = child.Color
				foundBodyParts[child.BodyPart] = true
			end
		end
	end
	return bodyColorsData
end

--[=[
	Returns whether all six body colors are present and equal.

	@within BodyColorsDataUtils
	@param bodyColorsData BodyColorsData
	@return boolean
]=]
function BodyColorsDataUtils.isUniformColor(bodyColorsData: BodyColorsData): boolean
	assert(isBodyColorsData(bodyColorsData), "Bad bodyColorsData")
	const headColor = bodyColorsData.headColor
	if headColor == nil then
		return false
	end
	return bodyColorsData.leftArmColor ~= nil
		and Color3Utils.areEqual(headColor, bodyColorsData.leftArmColor)
		and bodyColorsData.leftLegColor ~= nil
		and Color3Utils.areEqual(headColor, bodyColorsData.leftLegColor)
		and bodyColorsData.rightArmColor ~= nil
		and Color3Utils.areEqual(headColor, bodyColorsData.rightArmColor)
		and bodyColorsData.rightLegColor ~= nil
		and Color3Utils.areEqual(headColor, bodyColorsData.rightLegColor)
		and bodyColorsData.torsoColor ~= nil
		and Color3Utils.areEqual(headColor, bodyColorsData.torsoColor)
end

--[=[
	Returns the shared color when every body part has the same color.

	@within BodyColorsDataUtils
	@param bodyColorsData BodyColorsData
	@return Color3?
]=]
function BodyColorsDataUtils.getUniformColor(bodyColorsData: BodyColorsData): Color3?
	assert(isBodyColorsData(bodyColorsData), "Bad bodyColorsData")
	return if BodyColorsDataUtils.isUniformColor(bodyColorsData) then bodyColorsData.headColor else nil
end

--[=[
	Constructs a BodyColors instance from body-color data.

	@within BodyColorsDataUtils
	@param bodyColorsData BodyColorsData
	@return BodyColors
]=]
function BodyColorsDataUtils.toBodyColors(bodyColorsData: BodyColorsData): BodyColors
	assert(isBodyColorsData(bodyColorsData), "Bad bodyColorsData")
	const bodyColors = Instance.new("BodyColors")
	BodyColorsDataUtils.applyToBodyColors(bodyColorsData, bodyColors)
	return bodyColors
end

--[=[
	Applies body-color data to a BodyColors instance.

	@within BodyColorsDataUtils
	@param bodyColorsData BodyColorsData
	@param bodyColors BodyColors
]=]
function BodyColorsDataUtils.applyToBodyColors(bodyColorsData: BodyColorsData, bodyColors: BodyColors): ()
	assert(isBodyColorsData(bodyColorsData), "Bad bodyColorsData")
	assert(t.instanceIsA("BodyColors")(bodyColors), "Bad bodyColors")
	if bodyColorsData.headColor then
		bodyColors.HeadColor3 = bodyColorsData.headColor
	end
	if bodyColorsData.leftArmColor then
		bodyColors.LeftArmColor3 = bodyColorsData.leftArmColor
	end
	if bodyColorsData.leftLegColor then
		bodyColors.LeftLegColor3 = bodyColorsData.leftLegColor
	end
	if bodyColorsData.rightArmColor then
		bodyColors.RightArmColor3 = bodyColorsData.rightArmColor
	end
	if bodyColorsData.rightLegColor then
		bodyColors.RightLegColor3 = bodyColorsData.rightLegColor
	end
	if bodyColorsData.torsoColor then
		bodyColors.TorsoColor3 = bodyColorsData.torsoColor
	end
end

--[=[
	Reads body-color data from attributes.

	@within BodyColorsDataUtils
	@param instance Instance
	@return BodyColorsData
]=]
function BodyColorsDataUtils.fromAttributes(instance: Instance): BodyColorsData
	assert(t.Instance(instance), "Bad instance")
	const bodyColorsData = {} :: BodyColorsData
	for key, attributeName in BodyColorsDataConstants.ATTRIBUTE_MAPPING do
		const value = instance:GetAttribute(attributeName)
		if value ~= nil then
			if t.Color3(value) then
				(bodyColorsData :: any)[key] = value
			else
				warn(`[BodyColorsDataUtils] Attribute {attributeName} is not a Color3`)
			end
		end
	end
	return BodyColorsDataUtils.createBodyColorsData(bodyColorsData)
end

--[=[
	Stores body-color data as attributes, clearing absent colors.

	@within BodyColorsDataUtils
	@param instance Instance
	@param bodyColorsData BodyColorsData
]=]
function BodyColorsDataUtils.setAttributes(instance: Instance, bodyColorsData: BodyColorsData): ()
	assert(t.Instance(instance), "Bad instance")
	assert(isBodyColorsData(bodyColorsData), "Bad bodyColorsData")
	for key, attributeName in BodyColorsDataConstants.ATTRIBUTE_MAPPING do
		instance:SetAttribute(attributeName, (bodyColorsData :: any)[key])
	end
end

--[=[
	Applies body-color data to a HumanoidDescription's legacy color fields.

	@within BodyColorsDataUtils
	@param bodyColorsData BodyColorsData
	@param humanoidDescription HumanoidDescription
]=]
function BodyColorsDataUtils.applyToHumanoidDescription(
	bodyColorsData: BodyColorsData,
	humanoidDescription: HumanoidDescription
): ()
	assert(isBodyColorsData(bodyColorsData), "Bad bodyColorsData")
	assert(t.instanceIsA("HumanoidDescription")(humanoidDescription), "Bad humanoidDescription")
	for key, propertyName in BodyColorsDataConstants.ATTRIBUTE_MAPPING do
		const color = (bodyColorsData :: any)[key]
		if color then
			(humanoidDescription :: any)[propertyName] = color
		end
	end
end

return BodyColorsDataUtils
