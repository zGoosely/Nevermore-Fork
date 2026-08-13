--!strict
--[=[
	Resolves the game server's approximate region through IP geolocation.

	@util ServerRegionGeolocationUtils
	@server
]=]
const HttpPromise = require("@game/ReplicatedStorage/Packages/HttpPromise")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const ServerRegionServiceConstants = require("../Shared/ServerRegionServiceConstants")
const ServerRegionServiceUtils = require("../Shared/ServerRegionServiceUtils")

const ServerRegionGeolocationUtils = {}

--[=[
	Requests and validates the approximate region associated with this server's
	outbound IP address.

	@within ServerRegionGeolocationUtils
	@return Promise<string>
]=]
function ServerRegionGeolocationUtils.promiseRegion(): Promise.Promise<string>
	return HttpPromise.json(ServerRegionServiceConstants.GEOLOCATION_URL):Then(function(response: any): any
		const region = ServerRegionServiceUtils.formatGeolocationResponse(response)
		if not region then
			return Promise.rejected("Geolocation response did not contain a valid region")
		end

		return region
	end) :: any
end

return ServerRegionGeolocationUtils
