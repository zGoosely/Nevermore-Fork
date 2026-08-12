--!strict
--!optimize 2
--[=[
	Maintains distance-bucketed 3D spatial cells for client culling entries.

	@class ClientCullingSpatialIndex
]=]

const require = require("../Loader").load()

const ClientCullingTypes = require("ClientCullingTypes")
const ClientCullingUtils = require("ClientCullingUtils")
const Maid = require("Maid")
const t = require("t")

type CullEntry = ClientCullingTypes.CullEntry

type SpatialRecord = {
	Entry: CullEntry,
	BucketSize: number,
	CellX: number,
	CellY: number,
	CellZ: number,
	CellIndex: number,
}

type SpatialCell = { SpatialRecord }
type SpatialDepth = { [number]: SpatialCell }
type SpatialColumn = { [number]: SpatialDepth }

type SpatialBucket = {
	CellSize: number,
	Cells: { [number]: SpatialColumn },
}

const ClientCullingSpatialIndex = {}
ClientCullingSpatialIndex.ClassName = "ClientCullingSpatialIndex"
ClientCullingSpatialIndex.__index = ClientCullingSpatialIndex

export type ClientCullingSpatialIndex = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_buckets: { [number]: SpatialBucket },
		_records: { [CullEntry]: SpatialRecord },
	},
	{} :: typeof({ __index = ClientCullingSpatialIndex })
))

function ClientCullingSpatialIndex.new(): ClientCullingSpatialIndex
	const self = setmetatable({}, ClientCullingSpatialIndex) :: ClientCullingSpatialIndex
	self._maid = Maid.new()
	self._buckets = {}
	self._records = {}
	return self
end

--[=[
	Adds an entry or updates its current bucket and cell.

	@within ClientCullingSpatialIndex
	@param entry CullEntry
]=]
function ClientCullingSpatialIndex.AddOrUpdate(self: ClientCullingSpatialIndex, entry: CullEntry): ()
	assert(t.table(entry), "Bad entry")

	const bucketSize = ClientCullingUtils.getSpatialBucketSize(entry._config.CullDistance + entry._bounds.Radius)
	const position = entry._bounds.CFrame.Position
	const cellX, cellY, cellZ = self:_getCellCoordinates(position, bucketSize)
	const existing = self._records[entry]
	if
		existing
		and existing.BucketSize == bucketSize
		and existing.CellX == cellX
		and existing.CellY == cellY
		and existing.CellZ == cellZ
	then
		return
	end

	local record: SpatialRecord
	if existing then
		self:_unlinkRecord(existing)
		record = existing
	else
		record = {
			Entry = entry,
			BucketSize = bucketSize,
			CellX = cellX,
			CellY = cellY,
			CellZ = cellZ,
			CellIndex = 0,
		}
		self._records[entry] = record
	end

	record.BucketSize = bucketSize
	record.CellX = cellX
	record.CellY = cellY
	record.CellZ = cellZ
	self:_linkRecord(record)
end

--[=[
	Removes an entry from the index.

	@within ClientCullingSpatialIndex
	@param entry CullEntry
]=]
function ClientCullingSpatialIndex.Remove(self: ClientCullingSpatialIndex, entry: CullEntry): ()
	assert(t.table(entry), "Bad entry")

	const record = self._records[entry]
	if not record then
		return
	end

	self:_unlinkRecord(record)
	self._records[entry] = nil
end

--[=[
	Returns entries in cells whose bucket ranges can contain the position.

	@within ClientCullingSpatialIndex
	@param position Vector3
	@return { CullEntry }
]=]
function ClientCullingSpatialIndex.QueryNearby(self: ClientCullingSpatialIndex, position: Vector3): { CullEntry }
	assert(t.Vector3(position), "Bad position")

	const results = {}
	for _, bucket in self._buckets do
		const cellX, cellY, cellZ = self:_getCellCoordinates(position, bucket.CellSize)
		for queryX = cellX - 1, cellX + 1 do
			const column = bucket.Cells[queryX]
			if not column then
				continue
			end

			for queryY = cellY - 1, cellY + 1 do
				const depth = column[queryY]
				if not depth then
					continue
				end

				for queryZ = cellZ - 1, cellZ + 1 do
					const cell = depth[queryZ]
					if not cell then
						continue
					end

					for _, record in cell do
						table.insert(results, record.Entry)
					end
				end
			end
		end
	end
	return results
end

function ClientCullingSpatialIndex._getCellCoordinates(
	_self: ClientCullingSpatialIndex,
	position: Vector3,
	cellSize: number
): (number, number, number)
	return math.floor(position.X / cellSize), math.floor(position.Y / cellSize), math.floor(position.Z / cellSize)
end

function ClientCullingSpatialIndex._linkRecord(self: ClientCullingSpatialIndex, record: SpatialRecord): ()
	local bucket = self._buckets[record.BucketSize]
	if not bucket then
		bucket = {
			CellSize = record.BucketSize,
			Cells = {},
		}
		self._buckets[record.BucketSize] = bucket
	end

	local column = bucket.Cells[record.CellX]
	if not column then
		column = {}
		bucket.Cells[record.CellX] = column
	end

	local depth = column[record.CellY]
	if not depth then
		depth = {}
		column[record.CellY] = depth
	end

	local cell = depth[record.CellZ]
	if not cell then
		cell = {}
		depth[record.CellZ] = cell
	end

	record.CellIndex = #cell + 1
	table.insert(cell, record)
end

function ClientCullingSpatialIndex._unlinkRecord(self: ClientCullingSpatialIndex, record: SpatialRecord): ()
	const bucket = self._buckets[record.BucketSize]
	const column = bucket and bucket.Cells[record.CellX]
	const depth = column and column[record.CellY]
	const cell = depth and depth[record.CellZ]
	if not bucket or not column or not depth or not cell or cell[record.CellIndex] ~= record then
		return
	end

	const lastRecord = cell[#cell]
	cell[record.CellIndex] = lastRecord
	cell[#cell] = nil
	if lastRecord ~= record then
		lastRecord.CellIndex = record.CellIndex
	end
	record.CellIndex = 0

	if #cell == 0 then
		depth[record.CellZ] = nil
		if next(depth) == nil then
			column[record.CellY] = nil
			if next(column) == nil then
				bucket.Cells[record.CellX] = nil
				if next(bucket.Cells) == nil then
					self._buckets[record.BucketSize] = nil
				end
			end
		end
	end
end

function ClientCullingSpatialIndex.Destroy(self: ClientCullingSpatialIndex): ()
	self._maid:DoCleaning()
	table.clear(self._records)
	table.clear(self._buckets)
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return ClientCullingSpatialIndex
