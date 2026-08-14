--!strict
--[=[
    @utils BanServiceUtils
]=]

export type BanHistoryEntry = {
	Ban: boolean,
	Duration: number,
	PlaceId: number,
	StartTime: string,
}

const PERMANENT_DURATION = -1

const BanServiceUtils = {}

--[=[
    Does something

    @within BanServiceUtils
    @returns any
]=]
function BanServiceUtils.isActiveBan(entry: BanHistoryEntry): boolean
	if not entry.Ban then
		return false
	end

	if entry.Duration == PERMANENT_DURATION then
		return true
	end

	const startTime = DateTime.fromIsoDate(entry.StartTime)
	return DateTime.now().UnixTimestampMillis < startTime.UnixTimestampMillis + entry.Duration * 1000
end

return BanServiceUtils
