--!strict
--[=[
	Unit tests for server metadata validation and immutable snapshots.

	@class ServerListUtils.spec
]=]
const Jest = require("@game/ReplicatedStorage/Packages/Jest")
const ServerListUtils = require("./ServerListUtils")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

const metadata = {
	jobId = "job-123",
	placeId = 100,
	name = "Amber Otter 1",
	region = nil,
	regionSource = "unknown",
	playerCount = 2,
	maxPlayers = 20,
	serverType = "standard",
	placeVersion = 7,
	startedAt = 1000,
	updatedAt = 1010,
}

const currentServerMetadata = {
	jobId = if game.JobId ~= "" then game.JobId else `studio-{game.PlaceId}-{game.PlaceVersion}`,
	placeId = game.PlaceId,
	name = "Current Server",
	region = nil,
	regionSource = "unknown",
	playerCount = 0,
	maxPlayers = 20,
	serverType = "standard",
	placeVersion = game.PlaceVersion,
	startedAt = 1000,
	updatedAt = 1010,
}

describe("ServerListUtils", function()
	it("validates and freezes snapshots", function()
		expect(ServerListUtils.isServerMetadata(metadata)).toEqual(true)
		const snapshot = ServerListUtils.createSnapshot({ metadata })
		expect(table.isfrozen(snapshot)).toEqual(true)
		expect(table.isfrozen(snapshot[1])).toEqual(true)
	end)

	it("rejects impossible player counts", function()
		const invalid = table.clone(metadata)
		invalid.playerCount = 21
		expect(ServerListUtils.isServerMetadata(invalid)).toEqual(false)
	end)

	it("detects the current server", function()
		expect(ServerListUtils.isThisMyServer(currentServerMetadata)).toEqual(true)

		const otherServer = table.clone(currentServerMetadata)
		otherServer.jobId = `${currentServerMetadata.jobId}-other`
		expect(ServerListUtils.isThisMyServer(otherServer)).toEqual(false)
	end)
end)
