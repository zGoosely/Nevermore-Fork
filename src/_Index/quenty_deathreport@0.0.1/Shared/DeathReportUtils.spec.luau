--!strict
--[=[
	Unit tests for DeathReportUtils.

	@class DeathReportUtils.spec
]=]
const DeathReportUtils = require("./DeathReportUtils")
const Jest = require("@game/ReplicatedStorage/Packages/Jest")

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

	it("should accept generic Instance values in a constructed report", function()
		const adornee = Instance.new("Model")
		const weapon = Instance.new("Tool")
		const report = DeathReportUtils.create(adornee, nil, DeathReportUtils.createWeaponData(weapon))

		expect(DeathReportUtils.isDeathReport(report)).toEqual(true)
		expect(report.adornee).toEqual(adornee)
		expect(report.weaponData.weaponInstance).toEqual(weapon)

		weapon:Destroy()
		adornee:Destroy()
	end)
end)

describe("DeathReportUtils.getDefaultColor()", function()
	it("should return a Color3", function()
		const color = DeathReportUtils.getDefaultColor()
		expect(typeof(color)).toEqual("Color3")
	end)
end)
