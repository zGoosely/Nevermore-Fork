--!strict
--[=[
	Resolves the game server's approximate region through IP geolocation.

	@util ServerRegionGeolocationUtils
	@server
]=]

const require = require("../../Loader").load()

const HttpPromise = require("HttpPromise")
const Promise = require("Promise")
const ServerRegionServiceConstants = require("ServerRegionServiceConstants")
const ServerRegionServiceUtils = require("ServerRegionServiceUtils")

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
