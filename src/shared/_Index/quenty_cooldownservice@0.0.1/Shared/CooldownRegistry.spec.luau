--!strict
--[=[
	Unit tests for owner/key lookup, expiry, and prediction reconciliation.

	@class CooldownRegistry.spec
]=]
const Binder = require("@game/ReplicatedStorage/Packages/Binder")
const CooldownBase = require("./CooldownBase")
const CooldownRegistry = require("./CooldownRegistry")
const CooldownServiceConstants = require("./CooldownServiceConstants")
const CooldownServiceUtils = require("./CooldownServiceUtils")
const Jest = require("@game/ReplicatedStorage/Packages/Jest")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

local function createRegistry(clock, destroyAuthoritativeOnExpiry, reconcilePredictions)
	const binder = Binder.new("CooldownRegistrySpec", function()
		return {}
	end)
	binder:Init()

	return CooldownRegistry.new(binder :: any, clock, destroyAuthoritativeOnExpiry, reconcilePredictions), binder
end

describe("CooldownRegistry", function()
	it("indexes independently by owner and key and removes expired state", function()
		local currentTime = 10
		const clock = function()
			return currentTime
		end
		const registry, binder = createRegistry(clock, true, false)
		const firstOwner = Instance.new("Folder")
		const secondOwner = Instance.new("Folder")
		const firstFolder = CooldownServiceUtils.createCooldown(firstOwner, "Dash", 2, clock)
		const secondFolder = CooldownServiceUtils.createCooldown(secondOwner, "Dash", 4, clock)
		const first = CooldownBase.new(firstFolder, clock)
		const second = CooldownBase.new(secondFolder, clock)

		registry:Register(first :: any)
		registry:Register(second :: any)

		expect(registry:Get(firstOwner, "Dash")).toEqual(first)
		expect(registry:Get(secondOwner, "Dash")).toEqual(second)

		currentTime = 13
		expect(registry:Get(firstOwner, "Dash")).toEqual(nil)
		expect(firstFolder.Parent).toEqual(nil)
		expect(registry:Get(secondOwner, "Dash")).toEqual(second)

		registry:Destroy()
		first:Destroy()
		second:Destroy()
		binder:Destroy()
		firstOwner:Destroy()
		secondOwner:Destroy()
	end)

	it("selects authority and removes a matching prediction", function()
		const clock = function()
			return 20
		end
		const registry, binder = createRegistry(clock, false, true)
		const owner = Instance.new("Folder")
		const predictedFolder = CooldownServiceUtils.createCooldown(owner, "Barrage", 5, clock)
		predictedFolder:SetAttribute(CooldownServiceConstants.PREDICTED_ATTRIBUTE, true)
		const authoritativeFolder = CooldownServiceUtils.createCooldown(owner, "Barrage", 4, clock)
		authoritativeFolder:SetAttribute(CooldownServiceConstants.PREDICTED_ATTRIBUTE, false)
		const predicted = CooldownBase.new(predictedFolder, clock)
		const authoritative = CooldownBase.new(authoritativeFolder, clock)

		registry:Register(predicted :: any)
		expect(registry:Get(owner, "Barrage")).toEqual(predicted)

		registry:Register(authoritative :: any)
		expect(registry:Get(owner, "Barrage")).toEqual(authoritative)
		expect(predictedFolder.Parent).toEqual(nil)

		registry:Destroy()
		predicted:Destroy()
		authoritative:Destroy()
		binder:Destroy()
		owner:Destroy()
	end)
end)
