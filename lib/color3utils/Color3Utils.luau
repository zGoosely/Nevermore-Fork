--!strict
--[=[
	Utility methods for Roblox Color3 values
	@class Color3Utils
]=]

const require = require("../Loader").load()

local LuvUtils = require('LuvUtils')

local Color3Utils = {}

local LIGHTEN_DARKEN_DEFAULT_SCALAR = 2
local EPSILON = 1e-3

export type SerializedColor3 = { number }
export type LUVColor3 = { number }

--[=[
	Serializes a Color3 value into an RGB array (0–255)

	@within Color3Utils
	@param color3 Color3
	@return SerializedColor3
]=]
function Color3Utils.serializeColor3(color3: Color3): SerializedColor3
	return {
		math.floor(color3.R * 255),
		math.floor(color3.G * 255),
		math.floor(color3.B * 255),
	}
end

--[=[
	Creates a serialized Color3 from raw RGB values (0–255)

	@within Color3Utils
	@param r number
	@param g number
	@param b number
	@return SerializedColor3
]=]
function Color3Utils.serializeColor3fromRGB(r: number, g: number, b: number): SerializedColor3
	assert(type(r) == 'number', 'Bad r')
	assert(type(g) == 'number', 'Bad g')
	assert(type(b) == 'number', 'Bad b')

	return {
		r,
		g,
		b,
	}
end

--[=[
	Deserializes an RGB array (0–255) into a Color3

	@within Color3Utils
	@param color3 SerializedColor3
	@return Color3
]=]
function Color3Utils.deserializeFromColor3(color3: SerializedColor3): Color3
	assert(type(color3) == 'table', 'Bad color3')
	assert(#color3 == 3, 'Bad color3')

	return Color3.fromRGB(color3[1], color3[2], color3[3])
end

--[=[
	Mutates a Color3 using RGB space

	@within Color3Utils
	@param color Color3
	@param mutator (rgb: { R: number, G: number, B: number }) -> ()
	@return Color3
]=]
function Color3Utils.mutateRGB(color: Color3, mutator: (rgb: { R: number, G: number, B: number }) -> ())
	local rgb = {
		R = color.R,
		G = color.G,
		B = color.B,
	}
	mutator(rgb)
	return Color3.new(rgb.R, rgb.G, rgb.B)
end

--[=[
	Mutates a Color3 using HSV space (scaled to 0–255 internally)

	@within Color3Utils
	@param color Color3
	@param mutator (hsv: { H: number, S: number, V: number }) -> ()
	@return Color3
]=]
function Color3Utils.mutateHSV(color: Color3, mutator: (hsv: { H: number, S: number, V: number }) -> ())
	local h, s, v = Color3.toHSV(color)
	local hsv = {
		H = h * 255,
		S = s * 255,
		V = v * 255,
	}
	mutator(hsv)
	return Color3.fromHSV(hsv.H / 255, hsv.S / 255, hsv.V / 255)
end

--[=[
	Lightens a Color3 by reducing saturation and increasing value

	@within Color3Utils
	@param color Color3
	@param scalar number? -- Defaults to 2
	@return Color3
]=]
function Color3Utils.lighten(color: Color3, scalar: number?)
	return Color3Utils.mutateHSV(color, function(hsv)
		hsv.S = math.max(0, hsv.S / (scalar or LIGHTEN_DARKEN_DEFAULT_SCALAR))
		hsv.V = math.min(255, hsv.V * (scalar or LIGHTEN_DARKEN_DEFAULT_SCALAR))
	end)
end

--[=[
	Darkens a Color3 by increasing saturation and reducing value

	@within Color3Utils
	@param color Color3
	@param scalar number? -- Defaults to 2
	@return Color3
]=]
function Color3Utils.darken(color: Color3, scalar: number?)
	return Color3Utils.mutateHSV(color, function(hsv)
		hsv.S = math.min(255, hsv.S * (scalar or LIGHTEN_DARKEN_DEFAULT_SCALAR))
		hsv.V = math.max(0, hsv.V / (scalar or LIGHTEN_DARKEN_DEFAULT_SCALAR))
	end)
end

--[=[
	Calculates the relative luminance of a Color3 (WCAG standard)

	@within Color3Utils
	@param color Color3
	@return number
]=]
function Color3Utils.getRelativeLuminance(color: Color3): number
	local components = { color.R, color.G, color.B }
	local vals = {}
	for i, val in components do
		if val <= 0.03928 then
			vals[i] = val / 12.92
		else
			vals[i] = ((val + 0.055) / 1.055) ^ 2.4
		end
	end

	return 0.2126 * vals[1] + 0.7152 * vals[2] + 0.0722 * vals[3]
end

--[=[
	Determines if black text should be used on a given background color

	@within Color3Utils
	@param color Color3
	@return boolean
]=]
function Color3Utils.textShouldBeBlack(color: Color3): boolean
	return Color3Utils.getRelativeLuminance(color) > 0.179
end

--[=[
	Scales the value (brightness) component of a Color3

	@within Color3Utils
	@param color3 Color3
	@param percent number
	@return Color3
]=]
function Color3Utils.scaleValue(color3: Color3, percent: number): Color3
	local h, s, v = color3:ToHSV()
	return Color3.fromHSV(h, s, percent * v)
end

--[=[
	Sets the value (brightness) component of a Color3

	@within Color3Utils
	@param color3 Color3
	@param value number
	@return Color3
]=]
function Color3Utils.setValue(color3: Color3, value: number): Color3
	local h, s, _ = color3:ToHSV()
	return Color3.fromHSV(h, s, value)
end

--[=[
	Sets the hue component of a Color3

	@within Color3Utils
	@param color3 Color3
	@param hue number
	@return Color3
]=]
function Color3Utils.setHue(color3: Color3, hue: number): Color3
	local _, s, v = color3:ToHSV()
	return Color3.fromHSV(hue, s, v)
end

--[=[
	Scales the saturation of a Color3

	@within Color3Utils
	@param color3 Color3
	@param percent number
	@return Color3
]=]
function Color3Utils.scaleSaturation(color3: Color3, percent: number): Color3
	local h, s, v = color3:ToHSV()
	return Color3.fromHSV(h, percent * s, v)
end

--[=[
	Sets the saturation of a Color3

	@within Color3Utils
	@param color3 Color3
	@param saturation number
	@return Color3
]=]
function Color3Utils.setSaturation(color3: Color3, saturation: number): Color3
	local h, _, v = color3:ToHSV()
	return Color3.fromHSV(h, saturation, v)
end

--[=[
	Compares two Color3 values with optional epsilon tolerance

	@within Color3Utils
	@param a Color3
	@param b Color3
	@param epsilon number?
	@return boolean
]=]
function Color3Utils.areEqual(a: Color3, b: Color3, epsilon: number?): boolean
	local equalEpsilon = if epsilon then epsilon else 1e-6

	return math.abs(a.R - b.R) <= equalEpsilon
		and math.abs(a.G - b.G) <= equalEpsilon
		and math.abs(a.B - b.B) <= equalEpsilon
end

--[=[
	Converts a Color3 to a hexadecimal integer (0xRRGGBB)

	@within Color3Utils
	@param color3 Color3
	@return number
]=]
function Color3Utils.toHexInteger(color3: Color3): number
	assert(typeof(color3) == 'Color3', 'Bad color3')

	return bit32.bor(bit32.lshift(color3.R * 0xFF, 16), bit32.lshift(color3.G * 0xFF, 8), color3.B * 0xFF)
end

--[=[
	Converts a Color3 to a hexadecimal string (RRGGBB)

	@within Color3Utils
	@param color3 Color3
	@return string
]=]
function Color3Utils.toHexString(color3: Color3): string
	assert(typeof(color3) == 'Color3', 'Bad color3')

	return string.format('%06X', Color3Utils.toHexInteger(color3))
end

--[=[
	Converts a Color3 to a web hex string (#RRGGBB)

	@within Color3Utils
	@param color3 Color3
	@return string
]=]
function Color3Utils.toWebHexString(color3: Color3): string
	assert(typeof(color3) == 'Color3', 'Bad color3')

	return string.format('#%06X', Color3Utils.toHexInteger(color3))
end

--[=[
	Interpolates between two Color3 values in LUV space.

	@within Color3Utils
	@param color0 Color3
	@param color1 Color3
	@param t number
	@return Color3
]=]
function Color3Utils.lerpLuv(color0: Color3, color1: Color3, t: number): Color3
	assert(typeof(color0) == 'Color3', 'Bad color0')
	assert(typeof(color1) == 'Color3', 'Bad color1')
	assert(type(t) == 'number', 'Bad t')

	if t == 0 then
		return color0
	elseif t == 1 then
		return color1
	end

	local l0, u0, v0 = unpack(Color3Utils.fromLuvColor3(color0))
	local l1, u1, v1 = unpack(Color3Utils.fromLuvColor3(color1))

	local shortestAngle = ((((l1 - l0) % 360) + 540) % 360) - 180
	local l = l0 + shortestAngle * t
	local u = u0 + (u1 - u0) * t
	local v = v0 + (v1 - v0) * t

	return Color3Utils.toLuvColor3({ l, u, v })
end

--[=[
	Desaturates a Color3 in LUV space.

	@within Color3Utils
	@param color0 Color3
	@param proportion number
	@return Color3
]=]
function Color3Utils.desaturateLuv(color0: Color3, proportion: number): Color3
	local l0, u0, v0 = unpack(Color3Utils.fromLuvColor3(color0))
	return Color3Utils.toLuvColor3({ l0, u0 * math.clamp(1 - proportion, 0, 1), v0 })
end

--[=[
	Darkens a Color3 in LUV space.

	@within Color3Utils
	@param color0 Color3
	@param proportion number
	@return Color3
]=]
function Color3Utils.darkenLuv(color0: Color3, proportion: number): Color3
	local l0, u0, v0 = unpack(Color3Utils.fromLuvColor3(color0))
	return Color3Utils.toLuvColor3({ l0, u0, v0 * math.clamp(1 - proportion, 0, 1) })
end

--[=[
	Converts a Color3 into LUV space.

	@within Color3Utils
	@param color3 Color3
	@return LUVColor3
]=]
function Color3Utils.fromLuvColor3(color3: Color3): LUVColor3
	assert(typeof(color3) == 'Color3', 'Bad color3')
	return LuvUtils.rgb_to_hsluv({ color3.R, color3.G, color3.B })
end

--[=[
	Converts a LUV tuple into a Color3.

	@within Color3Utils
	@param luv LUVColor3
	@return Color3
]=]
function Color3Utils.toLuvColor3(luv: LUVColor3): Color3
	assert(type(luv) == 'table', 'Bad luv')

	local r, g, b = unpack(LuvUtils.hsluv_to_rgb(luv))
	return Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
end

--[=[
	Gets the current color for a ColorSequence at the given timestamp.

	@within Color3Utils
	@param colorSequence ColorSequence
	@param t number
	@return Color3
]=]
function Color3Utils.getColorFromSequence(colorSequence: ColorSequence, t: number): Color3
	assert(typeof(colorSequence) == 'ColorSequence', 'Bad colorSequence')
	assert(type(t) == 'number', 'Bad t')

	local keypoints = colorSequence.Keypoints
	if t <= keypoints[1].Time then
		return keypoints[1].Value
	end

	for i = 2, #keypoints do
		local point = keypoints[i]
		if point.Time < t then
			continue
		end

		local prevPoint = keypoints[i - 1]
		local denominator = point.Time - prevPoint.Time
		local scale = if denominator == 0 then 0 else math.clamp((t - prevPoint.Time) / denominator, 0, 1)
		return prevPoint.Value:Lerp(point.Value, scale)
	end

	return keypoints[#keypoints].Value
end

--[=[
	Makes stripes for color sequences.

	@within Color3Utils
	@param stripes number
	@param backgroundColor3 Color3
	@param stripeColor3 Color3
	@param percentStripeThickness number
	@param percentOffset number
	@return ColorSequence
]=]
function Color3Utils.stripeSequence(
	stripes: number,
	backgroundColor3: Color3,
	stripeColor3: Color3,
	percentStripeThickness: number,
	percentOffset: number
): ColorSequence
	percentOffset = percentOffset or 0
	percentStripeThickness = math.clamp(percentStripeThickness or 0.5, 0, 1)

	if percentStripeThickness <= EPSILON then
		return ColorSequence.new(backgroundColor3)
	elseif percentStripeThickness >= 1 - EPSILON then
		return ColorSequence.new(stripeColor3)
	end

	local timeWidth = 1 / stripes
	local timeOffset = percentOffset * timeWidth
	timeOffset = timeOffset + percentStripeThickness * timeWidth * 0.5
	timeOffset = timeOffset % timeWidth

	local waypoints: { ColorSequenceKeypoint } = {}
	for i = 0, stripes - 1 do
		local timestampStart = (i / stripes + timeOffset) % 1
		local timeStampMiddle = (timestampStart + timeWidth * (1 - percentStripeThickness)) % 1

		table.insert(waypoints, ColorSequenceKeypoint.new(timestampStart, backgroundColor3))
		table.insert(waypoints, ColorSequenceKeypoint.new(timeStampMiddle, stripeColor3))
	end

	table.sort(waypoints, function(a, b)
		return a.Time < b.Time
	end)

	local fullWaypoints: { ColorSequenceKeypoint } = {}
	table.insert(fullWaypoints, waypoints[1])

	for i = 2, #waypoints do
		local previous = waypoints[i - 1]
		local current = waypoints[i]

		if current.Time - EPSILON > previous.Time then
			table.insert(fullWaypoints, ColorSequenceKeypoint.new(current.Time - EPSILON, previous.Value))
		end

		table.insert(fullWaypoints, current)
	end

	local first = fullWaypoints[1]
	if first.Time >= EPSILON then
		local color: Color3
		if first.Value == backgroundColor3 then
			color = stripeColor3
		elseif first.Value == stripeColor3 then
			color = backgroundColor3
		else
			error('Bad comparison')
		end

		table.insert(fullWaypoints, 1, ColorSequenceKeypoint.new(first.Time - EPSILON, color))
		table.insert(fullWaypoints, 1, ColorSequenceKeypoint.new(0, color))
	else
		table.remove(fullWaypoints, 1)
		table.insert(fullWaypoints, 1, ColorSequenceKeypoint.new(0, first.Value))
	end

	local last = fullWaypoints[#fullWaypoints]
	if last.Time <= 1 - EPSILON then
		table.insert(fullWaypoints, ColorSequenceKeypoint.new(1, last.Value))
	else
		table.remove(fullWaypoints)
		table.insert(fullWaypoints, ColorSequenceKeypoint.new(1, last.Value))
	end

	return ColorSequence.new(fullWaypoints)
end

return Color3Utils
