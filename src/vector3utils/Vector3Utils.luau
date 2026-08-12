--!strict
--[=[
	Utilities involving Vector3 objects in Roblox.
	@class Vector3Utils
]=]

const require = require("../Loader").load()

local MathUtils = require("MathUtils")

local Vector3Utils = {}

--[=[
	Creates a Vector3 from a Vector2 in the XY plane

	@param vector2 Vector2
	@return Vector3
]=]
function Vector3Utils.fromVector2XY(vector2: Vector2): Vector3
	return Vector3.new(vector2.X, vector2.Y, 0)
end

--[=[
	Creates a Vector3 from a Vector2 in the XZ plane

	@param vector2 Vector2
	@return Vector3
]=]
function Vector3Utils.fromVector2XZ(vector2: Vector2): Vector3
	return Vector3.new(vector2.X, 0, vector2.Y)
end

--[=[
	Computes the angle between 2 vectors in radians

	@param a Vector3
	@param b Vector3
	@return number?
]=]
function Vector3Utils.getAngleRad(a: Vector3, b: Vector3): number?
	if a.Magnitude == 0 then
		return nil
	end

	return math.acos(a:Dot(b))
end

--[=[
	Reflects a vector over a unit normal

	@param vector Vector3
	@param unitNormal Vector3
	@return Vector3
]=]
function Vector3Utils.reflect(vector: Vector3, unitNormal: Vector3): Vector3
	return vector - 2 * (unitNormal * vector:Dot(unitNormal))
end

--[=[
	Computes the angle between 2 vectors in radians

	@param a Vector3
	@param b Vector3
	@return number
]=]
function Vector3Utils.angleBetweenVectors(a: Vector3, b: Vector3): number
	local u = b.Magnitude * a
	local v = a.Magnitude * b
	return 2 * math.atan2((v - u).Magnitude, (u + v).Magnitude)
end

--[=[
	Spherically lerps between start and finish

	@param start Vector3
	@param finish Vector3
	@param t number -- Amount to slerp. 0 is start, 1 is finish. beyond that is extended as expected.
	@return Vector3
]=]
function Vector3Utils.slerp(start: Vector3, finish: Vector3, t: number): Vector3
	local dot = math.clamp(start:Dot(finish), -1, 1)

	local theta = math.acos(dot) * t
	local relVec = (finish - start * dot).Unit
	return ((start * math.cos(theta)) + (relVec * math.sin(theta)))
end

--[=[
	Constrains a Vector3 into a cone.

	@param direction Vector3 -- The vector direction to constrain
	@param coneDirection Vector3 -- The direction of the cone.
	@param coneAngleRad -- Angle of the cone
	@return Vector3 -- Constrained angle
]=]
function Vector3Utils.constrainToCone(direction: Vector3, coneDirection: Vector3, coneAngleRad: number): Vector3
	local angle = Vector3Utils.angleBetweenVectors(direction, coneDirection)
	local coneHalfAngle = 0.5 * coneAngleRad

	if angle > coneHalfAngle then
		local proportion = coneHalfAngle / angle
		return Vector3Utils.slerp(coneDirection.Unit, direction.Unit, proportion) * direction.Magnitude
	end

	return direction
end

--[=[
	Rounds the vector to the nearest number

	```lua
	-- Snaps to a grid!
	local snapped = Vector3Utils.round(position, 4)
	```

	@param vector3 Vector3
	@param amount number
	@return Vector3
]=]
function Vector3Utils.round(vector3: Vector3, amount: number): Vector3
	return Vector3.new(
		MathUtils.round(vector3.X, amount),
		MathUtils.round(vector3.Y, amount),
		MathUtils.round(vector3.Z, amount)
	)
end

--[=[
	Checks if 2 Vector3 values are clsoe to each other

	@param a Vector3
	@param b Vector3
	@param epsilon number
	@return boolean
]=]
function Vector3Utils.areClose(a: Vector3, b: Vector3, epsilon: number): boolean
	assert(type(epsilon) == "number", "Bad epsilon")

	return math.abs(a.X - b.X) <= epsilon and math.abs(a.Y - b.Y) <= epsilon and math.abs(a.Z - b.Z) <= epsilon
end

--[=[
	Gets a uniformly distributed random unit vector.

	@return Vector3
]=]
function Vector3Utils.getRandomUnitVector(): Vector3
	local s = 2 * (math.random() - 0.5)
	local t = 2 * math.pi * math.random()
	local rx = s
	local m = math.sqrt(1 - s * s)
	local ry = m * math.cos(t)
	local rz = m * math.sin(t)

	return Vector3.new(rx, ry, rz)
end

local function gaussianRandomScalar(): number
	return math.sqrt(-2 * math.log(1 - math.random())) * math.cos(2 * math.pi * math.random())
end

--[=[
	Computes a gaussian random Vector3.

	@param mean Vector3
	@param spread Vector3
	@return Vector3
]=]
function Vector3Utils.gaussianRandom(mean: Vector3, spread: Vector3): Vector3
	return mean
		+ spread
			* Vector3.new(gaussianRandomScalar(), gaussianRandomScalar(), gaussianRandomScalar())
			/ math.sqrt(3)
end

--[=[
	Gets a uniformly distributed random unit Vector3 directed within an angle around the given direction.

	@param direction Vector3
	@param angleRad number
	@return Vector3
]=]
function Vector3Utils.getDirectedRandomUnitVector(direction: Vector3, angleRad: number): Vector3
	assert(typeof(direction) == "Vector3", "Bad direction")
	assert(type(angleRad) == "number", "Bad angleRad")

	local s = 1 - (1 - math.cos(angleRad)) * math.random()
	local t = 2 * math.pi * math.random()
	local rx = s
	local m = math.sqrt(1 - s * s)
	local ry = m * math.cos(t)
	local rz = m * math.sin(t)

	local dx, dy, dz = direction.X, direction.Y, direction.Z
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)

	if dx / d < -0.9999 then
		return Vector3.new(-rx, ry, rz)
	elseif dx / d < 0.9999 then
		local denominator = dy * dy + dz * dz
		local coef1 = (rx - dx * (dy * ry + dz * rz) / denominator) / d
		local coef2 = (dz * ry - dy * rz) / denominator
		return Vector3.new((dx * rx + dy * ry + dz * rz) / d, dy * coef1 + dz * coef2, dz * coef1 - dy * coef2)
	else
		return Vector3.new(rx, ry, rz)
	end
end

return Vector3Utils
