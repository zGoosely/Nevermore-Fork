--!strict
--[=[
	Shared constants describing the day/night cycle. Day is defined as the clock
	time window between sunrise and sunset; everything else is night.

	@constants DayNightConstants
]=]
return require("@game/ReplicatedStorage/Packages/TableUtils").deepReadonly({
	SUNRISE_CLOCK_TIME = 6,
	SUNSET_CLOCK_TIME = 18,
	HOURS_PER_DAY = 24,
	RATE_SMOOTHING_ALPHA = 0.1,
})
