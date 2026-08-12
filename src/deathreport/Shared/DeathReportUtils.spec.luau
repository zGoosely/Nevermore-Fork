--!strict
--[=[
	Unit tests for DeathReportUtils.

	@class DeathReportUtils.spec
]=]

const require = require("../../Loader").load()

const DeathReportUtils = require("DeathReportUtils")
const Jest = require("Jest")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("DeathReportUtils.isDeathReport(deathReport)", function()
	it("should return false for nil", function()
		expect(DeathReportUtils.isDeathReport(nil)).toEqual(false)
	end)

	it("should return false for a table with wrong type", function()
		expect(DeathReportUtils.isDeathReport({ type = "other" })).toEqual(false)
	end)
end)

describe("DeathReportUtils.getDefaultColor()", function()
	it("should return a Color3", function()
		const color = DeathReportUtils.getDefaultColor()
		expect(typeof(color)).toEqual("Color3")
	end)
end)
