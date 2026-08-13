--!strict
--[=[
	Validates, formats, and reads replicated server-region values.

	@util ServerRegionServiceUtils
]=]

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const AttributeUtils = require("@game/ReplicatedStorage/Packages/AttributeUtils")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const ServerRegionServiceConstants = require("./ServerRegionServiceConstants")
const t = require("@game/ReplicatedStorage/Packages/t")

const isGeolocationResponse = t.interface({
	country_iso = t.optional(t.string),
	region_name = t.string,
})

const ServerRegionServiceUtils = {}

--[=[
	Returns whether a value is a supported replicated server region.

	@within ServerRegionServiceUtils
	@param value any
	@return boolean
]=]
function ServerRegionServiceUtils.isRegion(value: any): boolean
	return t.string(value) and value ~= "" and #value <= ServerRegionServiceConstants.MAX_REGION_LENGTH
end

--[=[
	Formats a validated geolocation response as `Region, CC`, or returns nil when
	the response does not contain a usable region.

	@within ServerRegionServiceUtils
	@param response any
	@return string?
]=]
function ServerRegionServiceUtils.formatGeolocationResponse(response: any): string?
	if not isGeolocationResponse(response) then
		return nil
	end

	const regionName = response.region_name
	const countryCode = response.country_iso
	const region = if countryCode and countryCode ~= "" then `{regionName}, {countryCode}` else regionName

	return if ServerRegionServiceUtils.isRegion(region) then region else nil
end

--[=[
	Returns the currently replicated server region, or nil while unavailable.

	@within ServerRegionServiceUtils
	@return string?
]=]
function ServerRegionServiceUtils.getRegion(): string?
	const region = ReplicatedStorage:GetAttribute(ServerRegionServiceConstants.REGION_ATTRIBUTE)
	return if ServerRegionServiceUtils.isRegion(region) then region :: string else nil
end

--[=[
	Returns a promise that resolves once a valid server region is replicated.

	@within ServerRegionServiceUtils
	@return Promise<string>
]=]
function ServerRegionServiceUtils.promiseRegion(): Promise.Promise<string>
	return AttributeUtils.promiseAttribute(
		ReplicatedStorage,
		ServerRegionServiceConstants.REGION_ATTRIBUTE,
		ServerRegionServiceUtils.isRegion
	) :: any
end

return ServerRegionServiceUtils
