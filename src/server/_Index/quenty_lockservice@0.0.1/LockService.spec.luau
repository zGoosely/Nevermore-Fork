--!strict
--[=[
	Unit tests for keyed lock contention and lifecycle release.

	@class LockService.spec
]=]
const Jest = require("@game/ReplicatedStorage/Packages/Jest")
const LockService = require("./LockService")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

local function createService(): LockService.LockService
	const service = setmetatable({}, { __index = LockService }) :: any
	service:Init({})
	return service
end

describe("LockService", function()
	it("rejects contention and isolates owner/key scopes", function()
		const service = createService()
		const firstOwner = Instance.new("Folder")
		const secondOwner = Instance.new("Folder")
		const first = service:TryAcquire({
			Owner = firstOwner,
			Key = "Action",
			Timeout = 10,
		})

		expect(first).never.toEqual(nil)
		expect(service:TryAcquire({
			Owner = firstOwner,
			Key = "Other",
			Timeout = 10,
		})).never.toEqual(nil)
		const otherOwnerPermit = service:TryAcquire({
			Owner = secondOwner,
			Key = "Action",
			Timeout = 10,
		})
		expect(otherOwnerPermit).never.toEqual(nil)

		const firstPermit = first :: any
		firstPermit:Release()
		expect(service:IsLocked(firstOwner, "Action")).toEqual(false)
		expect(service:TryAcquire({
			Owner = firstOwner,
			Key = "Action",
			Timeout = 10,
		})).never.toEqual(nil)

		service:Destroy()
		firstOwner:Destroy()
		secondOwner:Destroy()
	end)

	it("releases when its owner is destroyed", function()
		const service = createService()
		const owner = Instance.new("Folder")
		const permit = service:TryAcquire({
			Owner = owner,
			Key = "Action",
			Timeout = 10,
		})

		owner:Destroy()

		expect((permit :: any):IsReleased()).toEqual(true)
		expect((permit :: any):GetReleaseReason()).toEqual("OwnerDestroyed")
		expect(service:IsLocked(owner, "Action")).toEqual(false)
		service:Destroy()
	end)

	it("releases after its required timeout", function()
		const service = createService()
		const owner = Instance.new("Folder")
		const permit = service:TryAcquire({
			Owner = owner,
			Key = "Action",
			Timeout = 0.01,
		})

		task.wait(0.03)

		expect((permit :: any):IsReleased()).toEqual(true)
		expect((permit :: any):GetReleaseReason()).toEqual("Timeout")
		expect(service:IsLocked(owner, "Action")).toEqual(false)
		service:Destroy()
		owner:Destroy()
	end)

	it("runs Promise work and releases automatically", function()
		const service = createService()
		const owner = Instance.new("Folder")
		const promise = service:RunAsync({
			Owner = owner,
			Key = "Inventory",
			Timeout = 5,
		}, function()
			return Promise.delayed(0.01):Then(function()
				return "updated"
			end)
		end)

		expect(promise).never.toEqual(nil)
		expect(service:RunAsync({
			Owner = owner,
			Key = "Inventory",
			Timeout = 5,
		}, function()
			return Promise.resolved()
		end)).toEqual(nil)

		task.wait(0.03)

		expect(service:IsLocked(owner, "Inventory")).toEqual(false)
		const succeeded, value = (promise :: any):GetResults()
		expect(succeeded).toEqual(true)
		expect(value).toEqual("updated")

		service:Destroy()
		owner:Destroy()
	end)
end)
