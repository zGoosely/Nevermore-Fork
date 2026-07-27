--!strict
--[=[
	Converts and interpolates Color3 values in perceptual HSLuv space.

	@util LuvColor3Utils
]=]

const require = require("../Loader").load()

const LuvUtils = require("LuvUtils")
const MathUtils = require("MathUtils")

export type LUVColor3 = { number }

const LuvColor3Utils = {}

--[=[
	Interpolates two colors in HSLuv space.

	@within LuvColor3Utils
	@param color0 Color3
	@param color1 Color3
	@param t number
	@return Color3
]=]
function LuvColor3Utils.lerp(color0: Color3, color1: Color3, t: number): Color3
	assert(typeof(color0) == "Color3", "Bad color0")
	assert(typeof(color1) == "Color3", "Bad color1")
	assert(type(t) == "number", "Bad t")

	if t == 0 then
		return color0
	elseif t == 1 then
		return color1
	end

	const h0, s0, l0 = table.unpack(LuvColor3Utils.fromColor3(color0))
	const h1, s1, l1 = table.unpack(LuvColor3Utils.fromColor3(color1))
	const shortestAngle = ((((h1 - h0) % 360) + 540) % 360) - 180
	return LuvColor3Utils.toColor3({
		h0 + shortestAngle * t,
		MathUtils.lerp(s0, s1, t),
		MathUtils.lerp(l0, l1, t),
	})
end

--[=[
	Desaturates a color by a proportion from zero to one.

	@within LuvColor3Utils
	@param color Color3
	@param proportion number
	@return Color3
]=]
function LuvColor3Utils.desaturate(color: Color3, proportion: number): Color3
	assert(typeof(color) == "Color3", "Bad color")
	assert(type(proportion) == "number", "Bad proportion")
	const h, s, l = table.unpack(LuvColor3Utils.fromColor3(color))
	return LuvColor3Utils.toColor3({ h, s * math.clamp(1 - proportion, 0, 1), l })
end

--[=[
	Darkens a color by a proportion from zero to one.

	@within LuvColor3Utils
	@param color Color3
	@param proportion number
	@return Color3
]=]
function LuvColor3Utils.darken(color: Color3, proportion: number): Color3
	assert(typeof(color) == "Color3", "Bad color")
	assert(type(proportion) == "number", "Bad proportion")
	const h, s, l = table.unpack(LuvColor3Utils.fromColor3(color))
	return LuvColor3Utils.toColor3({ h, s, l * math.clamp(1 - proportion, 0, 1) })
end

--[=[
	Converts a Color3 into an HSLuv tuple.

	@within LuvColor3Utils
	@param color Color3
	@return LUVColor3
]=]
function LuvColor3Utils.fromColor3(color: Color3): LUVColor3
	assert(typeof(color) == "Color3", "Bad color")
	return LuvUtils.rgb_to_hsluv({ color.R, color.G, color.B })
end

--[=[
	Converts an HSLuv tuple into Color3.

	@within LuvColor3Utils
	@param luv LUVColor3
	@return Color3
]=]
function LuvColor3Utils.toColor3(luv: LUVColor3): Color3
	assert(type(luv) == "table", "Bad luv")
	const r, g, b = table.unpack(LuvUtils.hsluv_to_rgb(luv))
	return Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
end

return LuvColor3Utils
