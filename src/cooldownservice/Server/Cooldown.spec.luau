--!strict
--[=[
	Unit tests for authoritative cooldown mutations.

	@class Cooldown.spec
]=]

const require = require("../../Loader").load()

const Cooldown = require("Cooldown")
const CooldownServiceUtils = require("CooldownServiceUtils")
const Jest = require("Jest")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("Cooldown", function()
	it("restarts, extends, reduces, and clears authoritative state", function()
		local currentTime = 100
		const clock = function()
			return currentTime
		end
		const owner = Instance.new("Folder")
		const folder = CooldownServiceUtils.createCooldown(owner, "Dash", 5, clock)
		const cooldown = Cooldown.new(folder, clock)

		expect(Cooldown.new(folder, clock)).toEqual(cooldown)
		expect(cooldown:GetRemainingTime()).toEqual(5)
		expect(cooldown:AddTime(2)).toEqual(true)
		expect(cooldown:GetEndsAt()).toEqual(107)

		expect(cooldown:RemoveTime(1)).toEqual(true)
		expect(cooldown:GetEndsAt()).toEqual(106)

		currentTime = 101
		cooldown:Restart(3)
		expect(cooldown:GetStartedAt()).toEqual(101)
		expect(cooldown:GetEndsAt()).toEqual(104)

		expect(cooldown:RemoveTime(3)).toEqual(true)
		expect(folder.Parent).toEqual(nil)

		cooldown:Destroy()
		owner:Destroy()
	end)
end)
