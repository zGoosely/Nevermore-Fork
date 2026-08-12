--!strict
--[=[
	Unit tests for local server-list filtering and ordering.

	@class ServerListFilters.spec
]=]

const require = require("../../Loader").load()

const Jest = require("Jest")
const ServerListFilters = require("ServerListFilters")
const TableUtils = require("TableUtils")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

const function createMetadata(jobId: string, playerCount: number, startedAt: number, region: string?)
	return {
		jobId = jobId,
		placeId = 100,
		name = `Server {jobId}`,
		region = region,
		regionSource = if region then "configured" else "unknown",
		playerCount = playerCount,
		maxPlayers = 20,
		serverType = "standard",
		placeVersion = 7,
		startedAt = startedAt,
		updatedAt = math.max(startedAt, os.time()),
	}
end

describe("ServerListFilters", function()
	it("filters unavailable servers and orders by player count", function()
		const servers = {
			createMetadata("empty", 0, os.time() - 10, nil),
			createMetadata("busy", 18, os.time() - 20, nil),
			createMetadata("full", 20, os.time() - 30, nil),
		}
		const filters = {
			ServerListFilters.new("Recent"),
			ServerListFilters.new("Available"),
			ServerListFilters.new("MostPlayers"),
		}

		const result = ServerListFilters.apply(servers, filters)
		expect(TableUtils.map(result, function(metadata)
			return metadata.jobId
		end)).toEqual({ "busy", "empty" })
	end)

	it("filters by region", function()
		const servers = {
			createMetadata("eu", 4, os.time() - 10, "Europe"),
			createMetadata("na", 4, os.time() - 10, "North America"),
		}

		const result = ServerListFilters.apply(servers, {
			ServerListFilters.new("Region", "Europe"),
		})
		expect(#result).toEqual(1)
		expect(result[1].jobId).toEqual("eu")
	end)

	it("creates immutable filter snapshots", function()
		const snapshot = ServerListFilters.createSnapshot({
			ServerListFilters.new("Recent"),
		})
		expect(table.isfrozen(snapshot)).toEqual(true)
		expect(table.isfrozen(snapshot[1])).toEqual(true)
	end)
end)
