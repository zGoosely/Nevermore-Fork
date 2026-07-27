--!strict
--[=[
	Unit tests for cooldown validation, Folder creation, and heap ordering.

	@class CooldownServiceUtils.spec
]=]

const CollectionService = game:GetService("CollectionService")
const RunService = game:GetService("RunService")

const require = require("../../Loader").load()

const CooldownServiceConstants = require("CooldownServiceConstants")
const CooldownServiceUtils = require("CooldownServiceUtils")
const CooldownTypes = require("CooldownTypes")
const Jest = require("Jest")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("CooldownServiceUtils", function()
	it("creates fully initialized tagged cooldown state", function()
		const owner = Instance.new("Folder")
		const folder = CooldownServiceUtils.createCooldown(owner, "Dash", 3, function()
			return 10
		end)
		const state = CooldownServiceUtils.readState(folder)

		expect(CollectionService:HasTag(folder, CooldownServiceConstants.TAG_NAME)).toEqual(true)
		expect(folder.Parent).toEqual(owner)
		expect(state).toEqual({
			Owner = owner,
			Key = "Dash",
			StartedAt = 10,
			EndsAt = 13,
			IsPredicted = RunService:IsClient(),
		})

		owner:Destroy()
	end)

	it("rejects incomplete state and recognizes valid public values", function()
		const folder = Instance.new("Folder")

		expect(CooldownServiceUtils.readState(folder)).toEqual(nil)
		expect(CooldownServiceUtils.isCooldownKey("HeavyPunch")).toEqual(true)
		expect(CooldownServiceUtils.isCooldownKey("")).toEqual(false)
		expect(CooldownServiceUtils.isDuration(0.25)).toEqual(true)
		expect(CooldownServiceUtils.isDuration(0)).toEqual(false)
		expect(CooldownServiceUtils.isFiniteNumber(math.huge)).toEqual(false)

		folder:Destroy()
	end)

	it("validates and resolves typed cooldown values", function()
		expect(CooldownServiceUtils.getBaseDuration(CooldownTypes.Default, {
			Duration = 2,
		})).toEqual(2)
		expect(CooldownServiceUtils.getBaseDuration(CooldownTypes.Burst, {
			Duration = 0.5,
			Count = 4,
			Window = 3,
			PenaltyDuration = 5,
		})).toEqual(0.5)

		expect(CooldownServiceUtils.isBurstCooldownValue({
			Duration = 1,
			Count = 1,
			Window = 3,
			PenaltyDuration = 5,
		})).toEqual(false)
		expect(CooldownServiceUtils.isBurstCooldownValue({
			Duration = 5,
			Count = 4,
			Window = 3,
			PenaltyDuration = 5,
		})).toEqual(false)
	end)

	it("orders heap entries by the earliest priority", function()
		const heap = {}
		CooldownServiceUtils.pushHeapEntry(heap, {
			Priority = 5,
			Value = "late",
			Version = 1,
		})
		CooldownServiceUtils.pushHeapEntry(heap, {
			Priority = 1,
			Value = "early",
			Version = 2,
		})
		CooldownServiceUtils.pushHeapEntry(heap, {
			Priority = 3,
			Value = "middle",
			Version = 3,
		})

		const early = CooldownServiceUtils.popHeapEntry(heap)
		const middle = CooldownServiceUtils.popHeapEntry(heap)
		const late = CooldownServiceUtils.popHeapEntry(heap)
		expect(if early then early.Value else nil).toEqual("early")
		expect(if middle then middle.Value else nil).toEqual("middle")
		expect(if late then late.Value else nil).toEqual("late")
		expect(CooldownServiceUtils.popHeapEntry(heap)).toEqual(nil)
	end)
end)
