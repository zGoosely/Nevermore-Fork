--!strict
--[=[
	Serializes Color3 values into compact DataStore-safe RGB arrays.

	@util Color3SerializationUtils
]=]

const t = require("@game/ReplicatedStorage/Packages/t")

export type SerializedColor3 = { number }

const isRgbChannel = t.numberConstrained(0, 255)
const isSerializedColor3 = t.strictArray(isRgbChannel, isRgbChannel, isRgbChannel)

const Color3SerializationUtils = {}

--[=[
	Serializes a Color3 into an RGB array whose channels range from zero to 255.

	@within Color3SerializationUtils
	@param color3 Color3
	@return SerializedColor3
]=]
function Color3SerializationUtils.serialize(color3: Color3): SerializedColor3
	assert(t.Color3(color3), "Bad color3")

	return {
		math.floor(color3.R * 255),
		math.floor(color3.G * 255),
		math.floor(color3.B * 255),
	}
end

--[=[
	Returns whether a value is a three-channel serialized Color3.

	@within Color3SerializationUtils
	@param value any
	@return boolean
]=]
function Color3SerializationUtils.isSerializedColor3(value: any): boolean
	return isSerializedColor3(value)
end

--[=[
	Creates a serialized Color3 from RGB channels ranging from zero to 255.

	@within Color3SerializationUtils
	@param red number
	@param green number
	@param blue number
	@return SerializedColor3
]=]
function Color3SerializationUtils.fromRGB(red: number, green: number, blue: number): SerializedColor3
	assert(isRgbChannel(red), "Bad red")
	assert(isRgbChannel(green), "Bad green")
	assert(isRgbChannel(blue), "Bad blue")

	return { red, green, blue }
end

--[=[
	Deserializes an RGB array into a Color3.

	@within Color3SerializationUtils
	@param serializedColor3 SerializedColor3
	@return Color3
]=]
function Color3SerializationUtils.deserialize(serializedColor3: SerializedColor3): Color3
	assert(isSerializedColor3(serializedColor3), "Bad serializedColor3")
	return Color3.fromRGB(serializedColor3[1], serializedColor3[2], serializedColor3[3])
end

return Color3SerializationUtils
