--!strict
--[=[
	Unit tests for rolling burst cooldown resolution.

	@class CooldownBurstTracker.spec
]=]
const CooldownBurstTracker = require("./CooldownBurstTracker")
const Jest = require("@game/ReplicatedStorage/Packages/Jest")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("CooldownBurstTracker", function()
	it("penalizes the configured use count inside a rolling window", function()
		local now = 10
		const tracker = CooldownBurstTracker.new(function()
			return now
		end)
		const owner = Instance.new("Folder")
		const value = {
			Duration = 0.5,
			Count = 4,
			Window = 3,
			PenaltyDuration = 3,
		}

		expect(tracker:RecordUse(owner, "Punch", value)).toEqual(0.5)
		now += 0.6
		expect(tracker:RecordUse(owner, "Punch", value)).toEqual(0.5)
		now += 0.6
		expect(tracker:RecordUse(owner, "Punch", value)).toEqual(0.5)
		now += 0.6
		expect(tracker:RecordUse(owner, "Punch", value)).toEqual(3)

		now += 3
		expect(tracker:RecordUse(owner, "Punch", value)).toEqual(0.5)

		tracker:Destroy()
		owner:Destroy()
	end)

	it("prunes expired uses and isolates owner/key histories", function()
		local now = 0
		const tracker = CooldownBurstTracker.new(function()
			return now
		end)
		const firstOwner = Instance.new("Folder")
		const secondOwner = Instance.new("Folder")
		const value = {
			Duration = 1,
			Count = 2,
			Window = 2,
			PenaltyDuration = 5,
		}

		expect(tracker:RecordUse(firstOwner, "Punch", value)).toEqual(1)
		now = 3
		expect(tracker:RecordUse(firstOwner, "Punch", value)).toEqual(1)
		expect(tracker:RecordUse(firstOwner, "Kick", value)).toEqual(1)
		expect(tracker:RecordUse(secondOwner, "Punch", value)).toEqual(1)
		expect(tracker:RecordUse(firstOwner, "Punch", value)).toEqual(5)

		tracker:Destroy()
		firstOwner:Destroy()
		secondOwner:Destroy()
	end)

	it("resets history explicitly and when the policy changes", function()
		const tracker = CooldownBurstTracker.new(function()
			return 10
		end)
		const owner = Instance.new("Folder")
		const value = {
			Duration = 1,
			Count = 2,
			Window = 3,
			PenaltyDuration = 5,
		}

		expect(tracker:RecordUse(owner, "Punch", value)).toEqual(1)
		expect(tracker:Reset(owner, "Punch")).toEqual(true)
		expect(tracker:Reset(owner, "Punch")).toEqual(false)
		expect(tracker:RecordUse(owner, "Punch", value)).toEqual(1)
		expect(tracker:RecordUse(owner, "Punch", {
			Duration = 1,
			Count = 3,
			Window = 3,
			PenaltyDuration = 5,
		})).toEqual(1)

		tracker:Destroy()
		owner:Destroy()
	end)
end)
