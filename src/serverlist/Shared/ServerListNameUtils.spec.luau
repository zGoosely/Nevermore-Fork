--!strict
--[=[
	Unit tests for deterministic server names and Studio job IDs.

	@class ServerListNameUtils.spec
]=]

const require = require("../../Loader").load()

const Jest = require("Jest")
const ServerListNameUtils = require("ServerListNameUtils")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("ServerListNameUtils", function()
	it("generates stable names", function()
		const first = ServerListNameUtils.generateName("job-123")
		const second = ServerListNameUtils.generateName("job-123")
		expect(first).toEqual(second)
	end)

	it("provides a deterministic Studio fallback", function()
		expect(ServerListNameUtils.resolveJobId("", 100, 7)).toEqual("studio-100-7")
	end)
end)
