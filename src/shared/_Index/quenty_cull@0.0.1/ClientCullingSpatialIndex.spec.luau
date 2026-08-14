--!strict
--[=[
	Unit tests for client culling spatial indexing.

	@class ClientCullingSpatialIndex.spec
]=]
const ClientCullingSpatialIndex = require("./ClientCullingSpatialIndex")
const Jest = require("@game/ReplicatedStorage/Packages/Jest")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

local function createEntry(position: Vector3, distance: number): any
	return {
		_config = {
			CullDistance = distance,
			UncullDistance = math.max(0, distance - 10),
			Dynamic = false,
		},
		_bounds = {
			CFrame = CFrame.new(position),
			Size = Vector3.one * 2,
			Radius = math.sqrt(3),
		},
	}
end

describe("ClientCullingSpatialIndex", function()
	it("moves and removes entries without leaving stale cells", function()
		const index = ClientCullingSpatialIndex.new()
		const entry = createEntry(Vector3.zero, 100)
		index:AddOrUpdate(entry)
		expect(table.find(index:QueryNearby(Vector3.zero), entry)).never.toEqual(nil)

		entry._bounds.CFrame = CFrame.new(1_000, 0, 0)
		index:AddOrUpdate(entry)
		expect(table.find(index:QueryNearby(Vector3.zero), entry)).toEqual(nil)
		expect(table.find(index:QueryNearby(Vector3.new(1_000, 0, 0)), entry)).never.toEqual(nil)

		index:Remove(entry)
		expect(table.find(index:QueryNearby(Vector3.new(1_000, 0, 0)), entry)).toEqual(nil)
		index:Destroy()
	end)

	it("indexes five thousand roots without duplicate query results", function()
		const index = ClientCullingSpatialIndex.new()
		const entries = table.create(5_000)
		for itemIndex = 1, 5_000 do
			const entry = createEntry(Vector3.new(itemIndex * 12, itemIndex % 7, 0), 200)
			table.insert(entries, entry)
			index:AddOrUpdate(entry)
		end

		const nearby = index:QueryNearby(Vector3.new(30_000, 0, 0))
		const found: { [any]: true } = {}
		for _, entry in nearby do
			expect(found[entry]).toEqual(nil)
			found[entry] = true
		end
		expect(#nearby > 0).toEqual(true)

		for _, entry in entries do
			index:Remove(entry)
		end
		expect(index:QueryNearby(Vector3.new(30_000, 0, 0))).toEqual({})
		index:Destroy()
	end)
end)
