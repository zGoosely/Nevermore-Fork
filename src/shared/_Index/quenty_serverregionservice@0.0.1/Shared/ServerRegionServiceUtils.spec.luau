--!strict
--[=[
	Unit tests for server-region validation and formatting.

	@class ServerRegionServiceUtils.spec
]=]
const Jest = require("@game/ReplicatedStorage/Packages/Jest")
const ServerRegionServiceUtils = require("./ServerRegionServiceUtils")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("ServerRegionServiceUtils", function()
	it("formats geolocation responses", function()
		expect(ServerRegionServiceUtils.formatGeolocationResponse({
			country_iso = "US",
			region_name = "Virginia",
		})).toEqual("Virginia, US")
		expect(ServerRegionServiceUtils.formatGeolocationResponse({
			region_name = "Seoul",
		})).toEqual("Seoul")
	end)

	it("rejects malformed geolocation responses", function()
		expect(ServerRegionServiceUtils.formatGeolocationResponse({})).toEqual(nil)
		expect(ServerRegionServiceUtils.formatGeolocationResponse({
			country_iso = "US",
			region_name = "",
		})).toEqual(nil)
		expect(ServerRegionServiceUtils.formatGeolocationResponse("Virginia")).toEqual(nil)
	end)

	it("validates replicated regions", function()
		expect(ServerRegionServiceUtils.isRegion("Virginia, US")).toEqual(true)
		expect(ServerRegionServiceUtils.isRegion("")).toEqual(false)
		expect(ServerRegionServiceUtils.isRegion(42)).toEqual(false)
	end)
end)
