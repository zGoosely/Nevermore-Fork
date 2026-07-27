--!strict
--[=[
	Unit tests for shared cooldown expiry scheduling.

	@class CooldownExpiryScheduler.spec
]=]

const require = require("../../Loader").load()

const CooldownExpiryScheduler = require("CooldownExpiryScheduler")
const Jest = require("Jest")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("CooldownExpiryScheduler", function()
	it("expires due entries and ignores stale reschedules", function()
		local currentTime = 0
		const expired = {}
		const scheduler = CooldownExpiryScheduler.new(function()
			return currentTime
		end, function(cooldown)
			table.insert(expired, cooldown)
		end)
		const first = {} :: any
		const second = {} :: any

		scheduler:Schedule(first, 2)
		scheduler:Schedule(first, 5)
		scheduler:Schedule(second, 3)

		currentTime = 2
		scheduler:Step()
		expect(expired).toEqual({})

		currentTime = 3
		scheduler:Step()
		expect(expired).toEqual({ second })

		currentTime = 5
		scheduler:Step()
		expect(expired).toEqual({ second, first })

		scheduler:Destroy()
	end)

	it("cancels entries without firing them", function()
		local currentTime = 0
		local expirationCount = 0
		const scheduler = CooldownExpiryScheduler.new(function()
			return currentTime
		end, function()
			expirationCount += 1
		end)
		const cooldown = {} :: any

		scheduler:Schedule(cooldown, 1)
		scheduler:Cancel(cooldown)
		currentTime = 2
		scheduler:Step()

		expect(expirationCount).toEqual(0)
		scheduler:Destroy()
	end)
end)
