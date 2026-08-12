--!strict
--[=[
	Provides deterministic UTC date buckets and timestamp calculations.

	@util DateTimeUtils
]=]

const require = require("../Loader").load()

const t = require("t")

const SECONDS_PER_DAY = 24 * 60 * 60

const DateTimeUtils = {}

const function assertUnixTimestamp(unixTimestamp: number, argumentName: string): ()
	assert(t.number(unixTimestamp) and unixTimestamp > -math.huge and unixTimestamp < math.huge, `Bad {argumentName}`)
end

--[=[
	Returns the Unix timestamp at the beginning of the timestamp's UTC day.

	@within DateTimeUtils
	@param unixTimestamp number
	@return number
]=]
function DateTimeUtils.getStartOfUtcDay(unixTimestamp: number): number
	assertUnixTimestamp(unixTimestamp, "unixTimestamp")

	return math.floor(unixTimestamp / SECONDS_PER_DAY) * SECONDS_PER_DAY
end

--[=[
	Returns the Unix timestamp at the beginning of the timestamp's UTC week.
	Weeks begin on Monday.

	@within DateTimeUtils
	@param unixTimestamp number
	@return number
]=]
function DateTimeUtils.getStartOfUtcWeek(unixTimestamp: number): number
	assertUnixTimestamp(unixTimestamp, "unixTimestamp")

	const startOfDay = DateTimeUtils.getStartOfUtcDay(unixTimestamp)
	const unixDay = math.floor(startOfDay / SECONDS_PER_DAY)
	const daysSinceMonday = (unixDay + 3) % 7

	return startOfDay - daysSinceMonday * SECONDS_PER_DAY
end

--[=[
	Returns the Unix timestamp at the beginning of the timestamp's UTC month.

	@within DateTimeUtils
	@param unixTimestamp number
	@return number
]=]
function DateTimeUtils.getStartOfUtcMonth(unixTimestamp: number): number
	assertUnixTimestamp(unixTimestamp, "unixTimestamp")

	const components = DateTime.fromUnixTimestamp(unixTimestamp):ToUniversalTime()
	return DateTime.fromUniversalTime(components.Year, components.Month, 1).UnixTimestamp
end

--[=[
	Returns a stable `YYYY-MM-DD` key for the timestamp's UTC day.

	@within DateTimeUtils
	@param unixTimestamp number
	@return string
]=]
function DateTimeUtils.getUtcDayKey(unixTimestamp: number): string
	assertUnixTimestamp(unixTimestamp, "unixTimestamp")

	const components = DateTime.fromUnixTimestamp(unixTimestamp):ToUniversalTime()
	return string.format("%04d-%02d-%02d", components.Year, components.Month, components.Day)
end

--[=[
	Returns the `YYYY-MM-DD` key of the Monday beginning the timestamp's UTC
	week. Using the week-start date avoids ambiguity around ISO week-years.

	@within DateTimeUtils
	@param unixTimestamp number
	@return string
]=]
function DateTimeUtils.getUtcWeekKey(unixTimestamp: number): string
	assertUnixTimestamp(unixTimestamp, "unixTimestamp")

	return DateTimeUtils.getUtcDayKey(DateTimeUtils.getStartOfUtcWeek(unixTimestamp))
end

--[=[
	Returns a stable `YYYY-MM` key for the timestamp's UTC month.

	@within DateTimeUtils
	@param unixTimestamp number
	@return string
]=]
function DateTimeUtils.getUtcMonthKey(unixTimestamp: number): string
	assertUnixTimestamp(unixTimestamp, "unixTimestamp")

	const components = DateTime.fromUnixTimestamp(unixTimestamp):ToUniversalTime()
	return string.format("%04d-%02d", components.Year, components.Month)
end

--[=[
	Returns the non-negative number of seconds until a target timestamp.

	When `currentUnixTimestamp` is omitted, the current wall-clock time is used.

	@within DateTimeUtils
	@param targetUnixTimestamp number
	@param currentUnixTimestamp number?
	@return number
]=]
function DateTimeUtils.getTimeUntil(targetUnixTimestamp: number, currentUnixTimestamp: number?): number
	assertUnixTimestamp(targetUnixTimestamp, "targetUnixTimestamp")
	if currentUnixTimestamp ~= nil then
		assertUnixTimestamp(currentUnixTimestamp, "currentUnixTimestamp")
	end

	const currentTime = currentUnixTimestamp or DateTime.now().UnixTimestampMillis / 1000
	return math.max(0, targetUnixTimestamp - currentTime)
end

--[=[
	Returns whether two Unix timestamps occur during the same UTC day.

	@within DateTimeUtils
	@param firstUnixTimestamp number
	@param secondUnixTimestamp number
	@return boolean
]=]
function DateTimeUtils.isSameUtcDay(firstUnixTimestamp: number, secondUnixTimestamp: number): boolean
	assertUnixTimestamp(firstUnixTimestamp, "firstUnixTimestamp")
	assertUnixTimestamp(secondUnixTimestamp, "secondUnixTimestamp")

	return DateTimeUtils.getStartOfUtcDay(firstUnixTimestamp) == DateTimeUtils.getStartOfUtcDay(secondUnixTimestamp)
end

return DateTimeUtils
