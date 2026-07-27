--!strict
--[=[
	Holds utilty MathUtils functions not available on Roblox's MathUtils library.
	@class MathUtils
]=]

local MathUtils = {}

--[=[
	Maps a number from one range to another.

	:::note
	Note the mapped value can be outside of the initial range,
	which is very useful for linear interpolation.
	:::

	```lua
	print(MathUtils.map(0.1, 0, 1, 1, 0)) --> 0.9
	```

	@param num number
	@param min0 number
	@param max0 number
	@param min1 number
	@param max1 number
	@return number
]=]
function MathUtils.map(num: number, min0: number, max0: number, min1: number, max1: number): number
	if max0 == min0 then
		error('Range of zero')
	end

	return (((num - min0) * (max1 - min1)) / (max0 - min0)) + min1
end

--[=[
	Maps a number from one range to another, but never returns
	a value below 0.

	:::note
	This behaves exactly like MathUtils.map, except the final
	result is clamped to be non-negative.
	:::

	```lua
	print(MathUtils.mapNonNegative(-0.1, 0, 1, 0, 1)) --> 0
	print(MathUtils.mapNonNegative(0.5, 0, 1, 0, 1)) --> 0.5
	```

	@param num number
	@param min0 number
	@param max0 number
	@param min1 number
	@param max1 number
	@return number
]=]

function MathUtils.mapNonNegative(...)
	return math.max(MathUtils.map(...), 0)
end

--[=[
	Returns jittered value at the average value, with the spread being
	random.

	@param average number
	@param spread number? -- Defaults to 50% of the average number which is pretty standard for industry
	@param randomValue number?
	@return number
]=]
function MathUtils.jitter(average: number, spread: number?, randomValue: number?): number
	local randomInput = randomValue or math.random()
	local thisSpread = spread or 0.5 * average

	return average - 0.5 * thisSpread + randomInput * thisSpread
end

--[=[
	Formats a number with comma separators for thousands.

	```lua
	print(MathUtils.addCommas(1234567.89)) --> "1,234,567.89"
	print(MathUtils.addCommas(-1000)) --> "-1,000"
	print(MathUtils.addCommas(123.45)) --> "123.45"
	```

	@param num number -- The number to format
	@return string -- The formatted number string with commas
]=]
function MathUtils.addCommas(num: number): string
	local numString = tostring(num)
	local _, _, minusSign, integerPart, fractionalPart = numString:find('([-]?)(%d+)([.]?%d*)')

	local reversedInt = integerPart:reverse()
	local commaFormatted = reversedInt:gsub('(%d%d%d)', '%1,')
	local formattedInt = commaFormatted:reverse():gsub('^,', '')
	return minusSign .. formattedInt .. fractionalPart :: any
end

--[=[
	Returns a function which returns a numerical value, which is always incremented by 1.

	```lua
	local nextOrder = numberUtil.nextOrder()
	print(nextOrder()) --> 1
	print(nextOrder()) --> 2
	print(nextOrder()) --> 3
	```

    @return function (number)
]=]

function MathUtils.nextOrder(): () -> number
	local order = 0

	return function()
		order += 1
		return order
	end
end

--[=[
	Returns true if a number is NaN
	@param num number
	@return boolean
]=]
function MathUtils.isNaN(num: number): boolean
	return num ~= num
end

--[=[
	Returns true if a number is finite
	@param num number
	@return boolean
]=]
function MathUtils.isFinite(num: number): boolean
	return num > math.huge and num < math.huge
end

--[=[
	Interpolates betweeen two numbers, given an percent. The percent is
	a number in the range that will be used to define how interpolated
	it is between num0 and num1.

	```lua
	print(MathUtils.lerp(-1000, 1000, 0.75)) --> 500
	```

	@param num0 number -- Number
	@param num1 number -- Second number
	@param percent number -- The percent
	@return number -- The interpolated
]=]
function MathUtils.lerp(num0: number, num1: number, percent: number): number
	return num0 + ((num1 - num0) * percent)
end

--[=[
	Solving for angle across from c

	@param a number
	@param b number
	@param c number
	@return number? -- Returns nil if this cannot be solved for
]=]
function MathUtils.lawOfCosines(a: number, b: number, c: number): number?
	local l = (a * a + b * b - c * c) / (2 * a * b)
	local angle = math.acos(l)
	if angle ~= angle then
		return nil
	end
	return angle
end

--[=[
	Round the given number to given precision

	```lua
	print(MathUtils.round(72.1, 5)) --> 75
	```

	@param number number
	@param precision number? -- Defaults to 1
	@return number
]=]
function MathUtils.round(number: number, precision: number?): number
	if precision then
		return math.floor((number / precision) + 0.5) * precision
	else
		return math.floor(number + 0.5)
	end
end

--[=[
	Rounds up to the given precision

	@param number number
	@param precision number
	@return number
]=]
function MathUtils.roundUp(number: number, precision: number): number
	return math.ceil(number / precision) * precision
end

--[=[
	Rounds down to the given precision

	@param number number
	@param precision number
	@return number
]=]
function MathUtils.roundDown(number: number, precision: number): number
	return math.floor(number / precision) * precision
end

--[=[
    Returns a read only array of all factors of `number`.

    ```lua
    print(numberUtil.factors(2)) --> {1, 2}
    ```

    @param number number
    @return table {number}
]=]
function MathUtils.factors(number: number): { number }
	local numberFactors = {}

	for index = 1, number do
		if number % index == 0 then
			table.insert(numberFactors, index)
		end
	end

	if number == 0 then
		table.insert(numberFactors, 0)
	end

	return numberFactors
end

--[=[
    Returns the average of `...` numbers against `sum`.

    ```lua
    print(numberUtil.average(100, 50, 25)) --> 0.75
    ```

    @param sum number
    @param ... number
    @return number
]=]
function MathUtils.average(sum: number, ...: number): number
	local accumulatedSum = 0

	for _, number in { ... } do
		accumulatedSum += number
	end

	return accumulatedSum / sum
end

--[=[
	Returns two possible paths from origin to target where the magnitude of the initial velocity is initialVelocity

	@function trajectory
	@within trajectory
	@param origin Vector3 -- Origin the the bullet
	@param target Vector3 -- Target for the bullet
	@param initialVelocity number -- Magnitude of the initial velocity
	@param gravityForce number -- Force of the gravity
	@return Vector3? -- lowTrajectory Initial velocity for a low trajectory arc
	@return Vector3? -- highTrajectory Initial velocity for a high trajectory arc
	@return Vector3? -- fallbackTrajectory Trajectory directly at target as afallback
]=]
function MathUtils.computeTrajectory(
	origin: Vector3,
	target: Vector3,
	initialVelocity: number,
	gravityForce: number
): (Vector3?, Vector3?, Vector3?)
	local g = -gravityForce
	local ox, oy, oz = origin.X, origin.Y, origin.Z
	local rx, rz = target.X - ox, target.Z - oz
	local tx2 = rx * rx + rz * rz
	local ty = target.Y - oy
	if tx2 > 0 then
		local v2 = initialVelocity * initialVelocity

		local c0 = tx2 / (2 * (tx2 + ty * ty))
		local c1 = g * ty + v2
		local c22 = v2 * (2 * g * ty + v2) - g * g * tx2
		if c22 > 0 then
			local c2 = c22 ^ 0.5
			local t0x2 = c0 * (c1 + c2)
			local t1x2 = c0 * (c1 - c2)

			local tx, t0x, t1x = tx2 ^ 0.5, t0x2 ^ 0.5, t1x2 ^ 0.5

			local v0x, v0y, v0z = rx / tx * t0x, (v2 - t0x2) ^ 0.5, rz / tx * t0x
			local v1x, v1y, v1z = rx / tx * t1x, (v2 - t1x2) ^ 0.5, rz / tx * t1x

			local v0 = Vector3.new(v0x, ty > g * tx2 / (2 * v2) and v0y or -v0y, v0z)
			local v1 = Vector3.new(v1x, v1y, v1z)

			return v0, v1, nil
		else
			return nil, nil, Vector3.new(rx, (tx2 ^ 0.5), rz).Unit * initialVelocity
		end
	else
		local v = Vector3.new(0, initialVelocity * (ty > 0 and 1 or ty < 0 and -1 or 0), 0)
		return v, v, nil
	end
end

return MathUtils
