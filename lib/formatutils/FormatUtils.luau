--!strict
--[=[
	Stateless utility for formatting numbers, durations, byte sizes, percentages,
	and ordinal rank strings.

	@util FormatUtils
]=]

const require = require("../Loader").load()

const t = require("t")

const FormatUtils = {}

const SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
const BYTE_UNITS = { "B", "KB", "MB", "GB", "TB", "PB" }

export type DurationFormatStyle = "Digital" | "Short" | "Full"

--[=[
	Formats a number into a compact abbreviated string with SI suffixes (e.g., 1.5K, 2.5M, 1B).

	```lua
	print(FormatUtils.formatCompact(1500)) --> "1.5K"
	print(FormatUtils.formatCompact(2500000, 2)) --> "2.50M"
	```

	@within FormatUtils
	@param value number
	@param decimals number? -- Optional decimal precision (defaults to 1 for abbreviated numbers)
	@return string
]=]
function FormatUtils.formatCompact(value: number, decimals: number?): string
	assert(t.number(value), "Bad value")
	assert(t.optional(t.number)(decimals), "Bad decimals")

	if value ~= value then
		return "NaN"
	end

	if value == 0 then
		return "0"
	end

	const isNegative = value < 0
	const absValue = math.abs(value)

	if absValue < 1000 then
		const numStr = if decimals then string.format(`%.{decimals}f`, absValue) else tostring(absValue)
		return if isNegative then `-{numStr}` else numStr
	end

	const tier = math.min(math.floor(math.log10(absValue) / 3), #SUFFIXES - 1)
	const scaled = absValue / (10 ^ (tier * 3))
	const precision = decimals or 1

	local formattedNumber: string
	if decimals == nil then
		formattedNumber = string.format(`%.{precision}f`, scaled):gsub("%.?0+$", "")
	else
		formattedNumber = string.format(`%.{precision}f`, scaled)
	end

	const result = `{formattedNumber}{SUFFIXES[tier + 1]}`
	return if isNegative then `-{result}` else result
end

--[=[
	Formats a number with comma separators for thousands.

	```lua
	print(FormatUtils.formatCommas(1234567.89)) --> "1,234,567.89"
	```

	@within FormatUtils
	@param value number
	@return string
]=]
function FormatUtils.formatCommas(value: number): string
	assert(t.number(value), "Bad value")

	if value ~= value then
		return "NaN"
	end

	const valueStr = tostring(value)
	const minusSign, integerPart, fractionalPart = string.match(valueStr, "^(%-?)(%d+)(%.?%d*)$")
	if not integerPart then
		return valueStr
	end

	const reversedInt = string.reverse(integerPart)
	const commaFormatted = string.gsub(reversedInt, "(%d%d%d)", "%1,")
	const formattedInt = string.gsub(string.reverse(commaFormatted), "^,", "")

	return `{minusSign or ""}{formattedInt}{fractionalPart or ""}`
end

--[=[
	Formats a duration in seconds into readable strings based on style.
	- `"Digital"`: `02:03` or `01:02:03`
	- `"Short"`: `2m 3s` or `1d 4h`
	- `"Full"`: `2 minutes 3 seconds` or `1 day 4 hours`

	```lua
	print(FormatUtils.formatDuration(123, "Digital")) --> "02:03"
	print(FormatUtils.formatDuration(123, "Short")) --> "2m 3s"
	```

	@within FormatUtils
	@param seconds number
	@param style DurationFormatStyle? -- Defaults to "Digital"
	@return string
]=]
function FormatUtils.formatDuration(seconds: number, style: DurationFormatStyle?): string
	assert(t.number(seconds), "Bad seconds")
	assert(t.optional(t.string)(style), "Bad style")

	const targetStyle = style or "Digital"
	const totalSeconds = math.max(0, math.floor(seconds))

	const days = math.floor(totalSeconds / 86400)
	const hours = math.floor((totalSeconds % 86400) / 3600)
	const minutes = math.floor((totalSeconds % 3600) / 60)
	const secs = totalSeconds % 60

	if targetStyle == "Digital" then
		if days > 0 then
			return string.format("%d:%02d:%02d:%02d", days, hours, minutes, secs)
		elseif hours > 0 then
			return string.format("%02d:%02d:%02d", hours, minutes, secs)
		else
			return string.format("%02d:%02d", minutes, secs)
		end
	elseif targetStyle == "Short" then
		const parts = {}
		if days > 0 then
			table.insert(parts, `{days}d`)
		end
		if hours > 0 then
			table.insert(parts, `{hours}h`)
		end
		if minutes > 0 then
			table.insert(parts, `{minutes}m`)
		end
		if secs > 0 or #parts == 0 then
			table.insert(parts, `{secs}s`)
		end
		return table.concat(parts, " ")
	elseif targetStyle == "Full" then
		const parts = {}
		if days > 0 then
			table.insert(parts, `{days} {if days == 1 then "day" else "days"}`)
		end
		if hours > 0 then
			table.insert(parts, `{hours} {if hours == 1 then "hour" else "hours"}`)
		end
		if minutes > 0 then
			table.insert(parts, `{minutes} {if minutes == 1 then "minute" else "minutes"}`)
		end
		if secs > 0 or #parts == 0 then
			table.insert(parts, `{secs} {if secs == 1 then "second" else "seconds"}`)
		end
		return table.concat(parts, " ")
	else
		error(`Unknown style: {targetStyle}`)
	end
end

--[=[
	Formats a ratio (0 to 1) or percentage into a formatted string (e.g. 75%, +12.5%).

	```lua
	print(FormatUtils.formatPercent(0.75)) --> "75%"
	print(FormatUtils.formatPercent(0.125, 1, true)) --> "+12.5%"
	```

	@within FormatUtils
	@param ratio number -- Number representing ratio (0.5 = 50%)
	@param decimals number? -- Decimal precision (defaults to 0)
	@param showSign boolean? -- Whether to prefix positive values with '+'
	@return string
]=]
function FormatUtils.formatPercent(ratio: number, decimals: number?, showSign: boolean?): string
	assert(t.number(ratio), "Bad ratio")
	assert(t.optional(t.number)(decimals), "Bad decimals")
	assert(t.optional(t.boolean)(showSign), "Bad showSign")

	const percentVal = ratio * 100
	const precision = decimals or 0
	const formattedNum = string.format(`%.{precision}f`, percentVal)

	const signPrefix = if showSign and percentVal > 0 then "+" else ""
	return `{signPrefix}{formattedNum}%`
end

--[=[
	Formats an integer into an ordinal string (1st, 2nd, 3rd, 4th, 21st, etc.).

	```lua
	print(FormatUtils.formatOrdinal(1)) --> "1st"
	print(FormatUtils.formatOrdinal(22)) --> "22nd"
	```

	@within FormatUtils
	@param value number
	@return string
]=]
function FormatUtils.formatOrdinal(value: number): string
	assert(t.number(value), "Bad value")

	const n = math.abs(math.floor(value))
	const tens = n % 100
	if tens >= 11 and tens <= 13 then
		return `{value}th`
	end

	const units = n % 10
	if units == 1 then
		return `{value}st`
	elseif units == 2 then
		return `{value}nd`
	elseif units == 3 then
		return `{value}rd`
	else
		return `{value}th`
	end
end

--[=[
	Formats a byte count into human-readable binary byte units (B, KB, MB, GB, TB).

	```lua
	print(FormatUtils.formatBytes(1048576)) --> "1.0 MB"
	```

	@within FormatUtils
	@param bytes number
	@param decimals number? -- Decimal precision (defaults to 1)
	@return string
]=]
function FormatUtils.formatBytes(bytes: number, decimals: number?): string
	assert(t.number(bytes), "Bad bytes")
	assert(t.optional(t.number)(decimals), "Bad decimals")

	if bytes <= 0 then
		return "0 B"
	end

	const precision = decimals or 1
	const index = math.min(math.floor(math.log(bytes, 1024)), #BYTE_UNITS - 1)
	const scaled = bytes / (1024 ^ index)

	return string.format(`%.{precision}f %s`, scaled, BYTE_UNITS[index + 1])
end

return FormatUtils
