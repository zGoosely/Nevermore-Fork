--!strict
--[=[
	Unit tests for client culling configuration and distance math.

	@class ClientCullingUtils.spec
]=]
const ClientCullingConstants = require("./ClientCullingConstants")
const ClientCullingUtils = require("./ClientCullingUtils")
const Jest = require("@game/ReplicatedStorage/Packages/Jest")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("ClientCullingUtils", function()
	it("resolves defaults and validates attribute combinations", function()
		const part = Instance.new("Part")
		const config = ClientCullingUtils.getConfig(part)
		expect(config).toEqual({
			CullDistance = ClientCullingConstants.DEFAULT_CULL_DISTANCE,
			UncullDistance = 190,
			Dynamic = false,
		})

		part:SetAttribute(ClientCullingConstants.CULL_DISTANCE_ATTRIBUTE, 80)
		part:SetAttribute(ClientCullingConstants.CULL_UNCULL_DISTANCE_ATTRIBUTE, 70)
		part:SetAttribute(ClientCullingConstants.CULL_DYNAMIC_ATTRIBUTE, true)
		expect(ClientCullingUtils.getConfig(part)).toEqual({
			CullDistance = 80,
			UncullDistance = 70,
			Dynamic = true,
		})

		part:SetAttribute(ClientCullingConstants.CULL_UNCULL_DISTANCE_ATTRIBUTE, 81)
		const invalidConfig, reason = ClientCullingUtils.getConfig(part)
		expect(invalidConfig).toEqual(nil)
		expect(reason).toEqual("CullUncullDistance must be between zero and CullDistance")
		part:Destroy()
	end)

	it("uses the closest point on oriented bounds", function()
		const bounds = {
			CFrame = CFrame.identity,
			Size = Vector3.new(10, 10, 10),
			Radius = math.sqrt(300) * 0.5,
		}

		expect(ClientCullingUtils.shouldCull(bounds, Vector3.new(13, 0, 0), 8)).toEqual(false)
		expect(ClientCullingUtils.shouldCull(bounds, Vector3.new(14, 0, 0), 8)).toEqual(true)
		expect(ClientCullingUtils.shouldCull(bounds, Vector3.zero, 0)).toEqual(false)
	end)

	it("derives bounds and power-of-two spatial buckets", function()
		const part = Instance.new("Part")
		part.CFrame = CFrame.new(4, 5, 6)
		part.Size = Vector3.new(2, 4, 6)

		const bounds = ClientCullingUtils.deriveBounds(part)
		expect(bounds).never.toEqual(nil)
		expect((bounds :: any).CFrame).toEqual(part.CFrame)
		expect((bounds :: any).Size).toEqual(part.Size)
		expect(ClientCullingUtils.getSpatialBucketSize(31)).toEqual(32)
		expect(ClientCullingUtils.getSpatialBucketSize(33)).toEqual(64)
		expect(ClientCullingUtils.getSpatialBucketSize(128)).toEqual(128)
		part:Destroy()
	end)
end)
