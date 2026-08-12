--!strict
--!optimize 2
--[=[
	Maintains a lightweight planar spatial hash for simulated characters.

	@class SimulatedCharacterSpatialHash
]=]

const require = require("../../Loader").load()

const Maid = require("Maid")

export type SpatialCharacter = {
	_id: number,
	_position: Vector2,
}

type SpatialEntry = {
	character: SpatialCharacter,
	cellX: number,
	cellZ: number,
	cellIndex: number,
}

type SpatialCell = { SpatialEntry }
type SpatialColumn = { [number]: SpatialCell }

const SimulatedCharacterSpatialHash = {}
SimulatedCharacterSpatialHash.ClassName = "SimulatedCharacterSpatialHash"
SimulatedCharacterSpatialHash.__index = SimulatedCharacterSpatialHash

export type SimulatedCharacterSpatialHash = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_cellSize: number,
		_cells: { [number]: SpatialColumn },
		_entries: { [SpatialCharacter]: SpatialEntry },
		_entryCount: number,
	},
	SimulatedCharacterSpatialHash
))

function SimulatedCharacterSpatialHash.new(cellSize: number): SimulatedCharacterSpatialHash
	assert(type(cellSize) == "number" and cellSize > 0 and cellSize < math.huge, "Bad cellSize")
	const self: SimulatedCharacterSpatialHash = setmetatable({} :: any, SimulatedCharacterSpatialHash)
	self._maid = Maid.new()
	self._cellSize = cellSize
	self._cells = {}
	self._entries = {}
	self._entryCount = 0
	return self
end

--[=[
	Adds a character to the spatial index. This operation is idempotent.

	@within SimulatedCharacterSpatialHash
	@param character SpatialCharacter
]=]
function SimulatedCharacterSpatialHash.AddCharacter(self: SimulatedCharacterSpatialHash, character: SpatialCharacter)
	if self._entries[character] then
		return
	end

	const cellX, cellZ = self:_getCellCoordinates(character._position)
	const entry: SpatialEntry = {
		character = character,
		cellX = cellX,
		cellZ = cellZ,
		cellIndex = 0,
	}
	self._entries[character] = entry
	self._entryCount += 1
	self:_linkEntry(entry)
end

--[=[
	Removes a character from the spatial index. This operation is idempotent.

	@within SimulatedCharacterSpatialHash
	@param character SpatialCharacter
]=]
function SimulatedCharacterSpatialHash.RemoveCharacter(self: SimulatedCharacterSpatialHash, character: SpatialCharacter)
	const entry = self._entries[character]
	if not entry then
		return
	end

	self:_unlinkEntry(entry)
	self._entries[character] = nil
	self._entryCount -= 1
end

--[=[
	Updates a character's occupied cell without allocating when the character
	remains in the same cell.

	@within SimulatedCharacterSpatialHash
	@param character SpatialCharacter
]=]
function SimulatedCharacterSpatialHash.UpdateCharacter(self: SimulatedCharacterSpatialHash, character: SpatialCharacter)
	const entry = self._entries[character]
	if not entry then
		self:AddCharacter(character)
		return
	end

	const cellX, cellZ = self:_getCellCoordinates(character._position)
	if entry.cellX == cellX and entry.cellZ == cellZ then
		return
	end

	self:_unlinkEntry(entry)
	entry.cellX = cellX
	entry.cellZ = cellZ
	self:_linkEntry(entry)
end

--[=[
	Updates every indexed character after one completed simulation step.

	@within SimulatedCharacterSpatialHash
	@param characters { SpatialCharacter }
]=]
function SimulatedCharacterSpatialHash.UpdateCharacters(
	self: SimulatedCharacterSpatialHash,
	characters: { SpatialCharacter }
)
	for _, character in characters do
		self:UpdateCharacter(character)
	end
end

--[=[
	Returns characters inside an X/Z radius, ordered nearest-first. Large queries
	automatically scan the dense entry map when that is cheaper than visiting
	empty hash cells.

	@within SimulatedCharacterSpatialHash
	@param position Vector2
	@param maxDistance number
	@return { SpatialCharacter }
]=]
function SimulatedCharacterSpatialHash.Query(
	self: SimulatedCharacterSpatialHash,
	position: Vector2,
	maxDistance: number
): { SpatialCharacter }
	assert(typeof(position) == "Vector2", "Bad position")
	assert(type(maxDistance) == "number" and maxDistance >= 0 and maxDistance < math.huge, "Bad maxDistance")
	if self._entryCount == 0 then
		return {}
	end

	const maximumDistanceSquared = maxDistance * maxDistance
	const results: { SpatialCharacter } = table.create(math.min(self._entryCount, 16))
	const estimatedAxisCellCount = math.ceil(maxDistance / self._cellSize) * 2 + 2
	const shouldScanEntries = estimatedAxisCellCount * estimatedAxisCellCount > self._entryCount

	if shouldScanEntries then
		for character in self._entries do
			const delta = character._position - position
			if delta:Dot(delta) <= maximumDistanceSquared then
				table.insert(results, character)
			end
		end
	else
		const minimumCellX = math.floor((position.X - maxDistance) / self._cellSize)
		const minimumCellZ = math.floor((position.Y - maxDistance) / self._cellSize)
		const maximumCellX = math.floor((position.X + maxDistance) / self._cellSize)
		const maximumCellZ = math.floor((position.Y + maxDistance) / self._cellSize)
		for cellX = minimumCellX, maximumCellX do
			const column = self._cells[cellX]
			if not column then
				continue
			end
			for cellZ = minimumCellZ, maximumCellZ do
				const cell = column[cellZ]
				if not cell then
					continue
				end
				for _, entry in cell do
					const character = entry.character
					const delta = character._position - position
					if delta:Dot(delta) <= maximumDistanceSquared then
						table.insert(results, character)
					end
				end
			end
		end
	end

	table.sort(results, function(first: SpatialCharacter, second: SpatialCharacter): boolean
		const firstDelta = first._position - position
		const secondDelta = second._position - position
		const firstDistanceSquared = firstDelta:Dot(firstDelta)
		const secondDistanceSquared = secondDelta:Dot(secondDelta)
		if firstDistanceSquared == secondDistanceSquared then
			return first._id < second._id
		end
		return firstDistanceSquared < secondDistanceSquared
	end)
	return results
end

function SimulatedCharacterSpatialHash._getCellCoordinates(
	self: SimulatedCharacterSpatialHash,
	position: Vector2
): (number, number)
	return math.floor(position.X / self._cellSize), math.floor(position.Y / self._cellSize)
end

function SimulatedCharacterSpatialHash._linkEntry(self: SimulatedCharacterSpatialHash, entry: SpatialEntry)
	local column = self._cells[entry.cellX]
	if not column then
		column = {}
		self._cells[entry.cellX] = column
	end
	local cell = column[entry.cellZ]
	if not cell then
		cell = {}
		column[entry.cellZ] = cell
	end

	entry.cellIndex = #cell + 1
	table.insert(cell, entry)
end

function SimulatedCharacterSpatialHash._unlinkEntry(self: SimulatedCharacterSpatialHash, entry: SpatialEntry)
	const column = self._cells[entry.cellX]
	const cell = column and column[entry.cellZ]
	if not cell or cell[entry.cellIndex] ~= entry then
		return
	end

	const lastEntry = cell[#cell]
	cell[entry.cellIndex] = lastEntry
	cell[#cell] = nil
	if lastEntry ~= entry then
		lastEntry.cellIndex = entry.cellIndex
	end
	entry.cellIndex = 0
	if #cell == 0 then
		column[entry.cellZ] = nil
		if next(column) == nil then
			self._cells[entry.cellX] = nil
		end
	end
end

function SimulatedCharacterSpatialHash.Destroy(self: SimulatedCharacterSpatialHash)
	self._maid:DoCleaning()
	table.clear(self._cells)
	table.clear(self._entries)
	table.clear(self)
	setmetatable(self, nil)
end

return SimulatedCharacterSpatialHash
