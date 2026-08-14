--!strict
--[=[
	Queries and observes whether it is currently day or night, and estimates how
	long until the next transition.

	Day/night is derived from `Lighting.ClockTime`: daytime is the window between
	sunrise and sunset (see [DayNightConstants]), and everything else is night.

	Time-until estimates are in real seconds and depend on how fast the game clock
	is advancing. The rate is measured live from `Lighting.ClockTime` changes, so a
	running day/night cycle is required for a finite estimate; a static clock
	reports `math.huge`.

	```lua
	DayNightUtils.observeIsDay():Subscribe(function(isDay)
		print(isDay and "Good morning" or "Good evening")
	end)

	DayNightUtils.observeTimeUntilNight():Subscribe(function(seconds)
		print(("%.0f real seconds until dusk"):format(seconds))
	end)
	```

	@util DayNightUtils
]=]
const Lighting = game:GetService("Lighting")

const DayNightConstants = require("./DayNightConstants")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const Rx = require("@game/ReplicatedStorage/Packages/Rx")
const RxInstanceUtils = require("@game/ReplicatedStorage/Packages/RxInstanceUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

const HOURS_PER_DAY = DayNightConstants.HOURS_PER_DAY
const SUNRISE = DayNightConstants.SUNRISE_CLOCK_TIME
const SUNSET = DayNightConstants.SUNSET_CLOCK_TIME
const ALPHA = DayNightConstants.RATE_SMOOTHING_ALPHA

type RateState = {
	clockTime: number,
	realTime: number,
	rate: number,
}

const DayNightUtils = {}

--[=[
	Returns whether the given clock time falls within daytime.

	@within DayNightUtils
	@param clockTime number -- Lighting.ClockTime hours in [0, 24)
	@return boolean
]=]
function DayNightUtils.isDay(clockTime: number): boolean
	assert(t.number(clockTime), "Bad clockTime")
	return clockTime >= SUNRISE and clockTime < SUNSET
end

--[=[
	Returns whether the given clock time falls within nighttime.

	@within DayNightUtils
	@param clockTime number -- Lighting.ClockTime hours in [0, 24)
	@return boolean
]=]
function DayNightUtils.isNight(clockTime: number): boolean
	assert(t.number(clockTime), "Bad clockTime")
	return not DayNightUtils.isDay(clockTime)
end

--[=[
	Returns the clock hours remaining until the next sunrise. Returns 0 exactly at
	sunrise, and a full day out if sunrise just passed.

	@within DayNightUtils
	@param clockTime number
	@return number
]=]
function DayNightUtils.getClockHoursUntilDay(clockTime: number): number
	assert(t.number(clockTime), "Bad clockTime")
	return (SUNRISE - clockTime) % HOURS_PER_DAY
end

--[=[
	Returns the clock hours remaining until the next sunset.

	@within DayNightUtils
	@param clockTime number
	@return number
]=]
function DayNightUtils.getClockHoursUntilNight(clockTime: number): number
	assert(t.number(clockTime), "Bad clockTime")
	return (SUNSET - clockTime) % HOURS_PER_DAY
end

--[=[
	Converts a span of clock hours into real seconds given how fast the clock is
	advancing. Returns `math.huge` when the clock is not advancing.

	@within DayNightUtils
	@param clockHours number -- clock hours remaining
	@param clockHoursPerSecond number -- measured clock advancement rate
	@return number
]=]
function DayNightUtils.getRealSecondsForClockHours(clockHours: number, clockHoursPerSecond: number): number
	assert(t.number(clockHours), "Bad clockHours")
	assert(t.number(clockHoursPerSecond), "Bad clockHoursPerSecond")

	if clockHoursPerSecond <= 0 then
		return math.huge
	end

	return clockHours / clockHoursPerSecond
end

--[=[
	Observes the current `Lighting.ClockTime`, emitting on every change.

	@within DayNightUtils
	@return Observable<number>
]=]
function DayNightUtils.observeClockTime(): Observable.Observable<number>
	return RxInstanceUtils.observeProperty(Lighting, "ClockTime") :: any
end

--[=[
	Observes whether it is currently daytime, emitting only on transitions.

	@within DayNightUtils
	@return Observable<boolean>
]=]
function DayNightUtils.observeIsDay(): Observable.Observable<boolean>
	return DayNightUtils.observeClockTime():Pipe({
		Rx.map(DayNightUtils.isDay) :: any,
		Rx.distinct(),
	}) :: any
end

--[=[
	Observes whether it is currently nighttime, emitting only on transitions.

	@within DayNightUtils
	@return Observable<boolean>
]=]
function DayNightUtils.observeIsNight(): Observable.Observable<boolean>
	return DayNightUtils.observeClockTime():Pipe({
		Rx.map(DayNightUtils.isNight) :: any,
		Rx.distinct(),
	}) :: any
end

--[=[
	Observes the measured clock advancement rate in clock hours per real second.
	Emits 0 until enough samples exist, and stays 0 while the clock is static. The
	value is smoothed to absorb frame-time jitter.

	@within DayNightUtils
	@return Observable<number>
]=]
function DayNightUtils.observeClockRate(): Observable.Observable<number>
	return DayNightUtils.observeClockTime():Pipe({
		Rx.scan(function(state: RateState?, clockTime: number): RateState
			const now = os.clock()

			if not state then
				return {
					clockTime = clockTime,
					realTime = now,
					rate = 0,
				}
			end

			const deltaReal = now - state.realTime
			if deltaReal <= 0 then
				return state
			end

			-- Clock advances forward and wraps at 24, so treat any decrease as a wrap.
			const deltaClock = (clockTime - state.clockTime) % HOURS_PER_DAY
			const instantRate = deltaClock / deltaReal

			return {
				clockTime = clockTime,
				realTime = now,
				rate = state.rate + ALPHA * (instantRate - state.rate),
			}
		end) :: any,
		Rx.map(function(state: RateState): number
			return state.rate
		end),
	}) :: any
end

--[=[
	Observes the estimated real seconds until the next sunrise. Emits `math.huge`
	while the clock is static.

	@within DayNightUtils
	@return Observable<number>
]=]
function DayNightUtils.observeTimeUntilDay(): Observable.Observable<number>
	return Rx.combineLatest({
		clockTime = DayNightUtils.observeClockTime(),
		rate = DayNightUtils.observeClockRate(),
	}):Pipe({
		Rx.map(function(state: { clockTime: number, rate: number }): number
			const clockHours = DayNightUtils.getClockHoursUntilDay(state.clockTime)
			return DayNightUtils.getRealSecondsForClockHours(clockHours, state.rate)
		end) :: any,
	}) :: any
end

--[=[
	Observes the estimated real seconds until the next sunset. Emits `math.huge`
	while the clock is static.

	@within DayNightUtils
	@return Observable<number>
]=]
function DayNightUtils.observeTimeUntilNight(): Observable.Observable<number>
	return Rx.combineLatest({
		clockTime = DayNightUtils.observeClockTime(),
		rate = DayNightUtils.observeClockRate(),
	}):Pipe({
		Rx.map(function(state: { clockTime: number, rate: number }): number
			const clockHours = DayNightUtils.getClockHoursUntilNight(state.clockTime)
			return DayNightUtils.getRealSecondsForClockHours(clockHours, state.rate)
		end) :: any,
	}) :: any
end

return DayNightUtils
