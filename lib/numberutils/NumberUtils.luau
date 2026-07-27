--!strict
--[=[
	Utility functions involving NumberRanges and NumberSequences on Roblox
	@class NumberUtils
]=]

const require = require("../Loader").load()

local Math = require('MathUtils')

local NumberUtils = {}

local EPSILON = 1e-3

--[=[
	Scales a NumberRange by the given amount.

	@param numberRange NumberRange
	@param scale number
	@return NumberRange
]=]
function NumberUtils.scaleRange(numberRange: NumberRange, scale: number): NumberRange
	assert(typeof(numberRange) == 'NumberRange', 'Bad numberRange')
	assert(type(scale) == 'number', 'Bad scale')

	return NumberRange.new(numberRange.Min * scale, numberRange.Max * scale)
end

--[=[
	Gets a NumberRange value at t.

	@param numberRange NumberRange
	@param t number
	@return number
]=]
function NumberUtils.getRangeValue(numberRange: NumberRange, t: number): number
	assert(typeof(numberRange) == 'NumberRange', 'Bad numberRange')
	assert(type(t) == 'number', 'Bad t')

	return numberRange.Min + (numberRange.Max - numberRange.Min) * t
end

--[=[
	Gets a generator for NumberSequence values at a given t.

	@param numberSequence NumberSequence
	@return (number) -> number
]=]
function NumberUtils.getSequenceValueGenerator(
	numberSequence: NumberSequence
): (number) -> number
	assert(typeof(numberSequence) == 'NumberSequence', 'Bad numberSequence')

	local keypoints = numberSequence.Keypoints
	if #keypoints == 1 then
		local keypoint = keypoints[1]
		if keypoint.Envelope == 0 then
			return function(t)
				assert(type(t) == 'number', 'Bad t')

				return keypoint.Value
			end
		else
			return function(t)
				assert(type(t) == 'number', 'Bad t')

				return keypoint.Value + (math.random() - 0.5) * keypoint.Envelope
			end
		end
	elseif #keypoints == 2 then
		local first = keypoints[1]
		local second = keypoints[2]

		if
			first.Value == second.Value
			and first.Envelope == 0
			and second.Envelope == 0
		then
			return function(t)
				assert(type(t) == 'number', 'Bad t')

				return first.Value
			end
		else
			local firstValue = first.Value + (math.random() - 0.5) * first.Envelope
			local secondValue = second.Value + (math.random() - 0.5) * second.Envelope
			return function(t)
				assert(type(t) == 'number', 'Bad t')
				local scale = math.clamp(Math.map(t, first.Time, second.Time, 0, 1), 0, 1)
				return Math.lerp(firstValue, secondValue, scale)
			end
		end
	else
		local values = {}
		for i = 1, #keypoints do
			local point = keypoints[i]
			values[i] = point.Value + (math.random() - 0.5) * point.Envelope
		end

		return function(t)
			assert(type(t) == 'number', 'Bad t')

			if t <= keypoints[1].Time then
				return values[1]
			end

			for i = 2, #keypoints do
				local point = keypoints[i]
				if point.Time < t then
					continue
				end

				local prevPoint = keypoints[i - 1]
				local scale =
					math.clamp(Math.map(t, prevPoint.Time, point.Time, 0, 1), 0, 1)
				return Math.lerp(values[i - 1], values[i], scale)
			end

			return values[#keypoints]
		end
	end
end

--[=[
	Maps each NumberSequence keypoint value through a callback.

	@param sequence NumberSequence
	@param callback (number) -> number
	@return NumberSequence
]=]
function NumberUtils.forEachSequenceValue(
	sequence: NumberSequence,
	callback: (number) -> number
): NumberSequence
	assert(type(callback) == 'function', 'Bad callback')

	local waypoints = {}
	local keypoints = sequence.Keypoints
	for _, keypoint in keypoints do
		table.insert(
			waypoints,
			NumberSequenceKeypoint.new(
				keypoint.Time,
				callback(keypoint.Value),
				keypoint.Envelope
			)
		)
	end

	return NumberSequence.new(waypoints)
end

--[=[
	Scales a NumberSequence by the given amount.

	@param sequence NumberSequence
	@param scale number
	@return NumberSequence
]=]
function NumberUtils.scaleSequence(
	sequence: NumberSequence,
	scale: number
): NumberSequence
	local waypoints = {}
	local keypoints = sequence.Keypoints
	for _, keypoint in keypoints do
		table.insert(
			waypoints,
			NumberSequenceKeypoint.new(
				keypoint.Time,
				keypoint.Value * scale,
				keypoint.Envelope * scale
			)
		)
	end

	return NumberSequence.new(waypoints)
end

--[=[
	Scales NumberSequence transparency values.

	@param sequence NumberSequence
	@param scale number
	@return NumberSequence
]=]
function NumberUtils.scaleSequenceTransparency(
	sequence: NumberSequence,
	scale: number
): NumberSequence
	local waypoints = {}
	local keypoints = sequence.Keypoints
	for _, keypoint in keypoints do
		table.insert(
			waypoints,
			NumberSequenceKeypoint.new(
				keypoint.Time,
				Math.map(keypoint.Value, 0, 1, scale, 1),
				keypoint.Envelope * scale
			)
		)
	end

	return NumberSequence.new(waypoints)
end

--[=[
	Generates a striped NumberSequence.

	@param stripes number
	@param backgroundTransparency number
	@param stripeTransparency number
	@param percentStripeThickness number
	@param percentOffset number
	@return NumberSequence
]=]
function NumberUtils.stripeSequence(
	stripes: number,
	backgroundTransparency: number,
	stripeTransparency: number,
	percentStripeThickness: number,
	percentOffset: number
): NumberSequence
	percentOffset = percentOffset or 0
	percentStripeThickness = math.clamp(percentStripeThickness or 0.5, 0, 1)

	if percentStripeThickness <= EPSILON then
		return NumberSequence.new(backgroundTransparency)
	elseif percentStripeThickness >= 1 - EPSILON then
		return NumberSequence.new(stripeTransparency)
	end

	local timeWidth = 1 / stripes
	local timeOffset = percentOffset * timeWidth
	timeOffset = timeOffset + percentStripeThickness * timeWidth * 0.5
	timeOffset = timeOffset % timeWidth

	local waypoints: { NumberSequenceKeypoint } = {}
	for i = 0, stripes - 1 do
		local timestampStart = (i / stripes + timeOffset) % 1
		local timeStampMiddle = (
			timestampStart + timeWidth * (1 - percentStripeThickness)
		) % 1

		table.insert(
			waypoints,
			NumberSequenceKeypoint.new(timestampStart, backgroundTransparency)
		)
		table.insert(
			waypoints,
			NumberSequenceKeypoint.new(timeStampMiddle, stripeTransparency)
		)
	end

	table.sort(waypoints, function(a, b)
		return a.Time < b.Time
	end)

	local fullWaypoints: { NumberSequenceKeypoint } = {}
	table.insert(fullWaypoints, waypoints[1])

	for i = 2, #waypoints do
		local previous = waypoints[i - 1]
		local current = waypoints[i]

		if current.Time - EPSILON > previous.Time then
			table.insert(
				fullWaypoints,
				NumberSequenceKeypoint.new(current.Time - EPSILON, previous.Value)
			)
		end

		table.insert(fullWaypoints, current)
	end

	local first = fullWaypoints[1]
	if first.Time >= EPSILON then
		local transparency: number
		if first.Value == backgroundTransparency then
			transparency = stripeTransparency
		elseif first.Value == stripeTransparency then
			transparency = backgroundTransparency
		else
			error('Bad comparison')
		end

		table.insert(
			fullWaypoints,
			1,
			NumberSequenceKeypoint.new(first.Time - EPSILON, transparency)
		)
		table.insert(fullWaypoints, 1, NumberSequenceKeypoint.new(0, transparency))
	else
		table.remove(fullWaypoints, 1)
		table.insert(fullWaypoints, 1, NumberSequenceKeypoint.new(0, first.Value))
	end

	local last = fullWaypoints[#fullWaypoints]
	if last.Time <= (1 - EPSILON) then
		table.insert(fullWaypoints, NumberSequenceKeypoint.new(1, last.Value))
	else
		table.remove(fullWaypoints)
		table.insert(fullWaypoints, NumberSequenceKeypoint.new(1, last.Value))
	end

	return NumberSequence.new(fullWaypoints)
end

return NumberUtils
