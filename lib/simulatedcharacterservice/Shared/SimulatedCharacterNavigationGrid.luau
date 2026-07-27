--!strict
--!optimize 2
--[=[
	A flat, tag-driven navigation grid with shared flow fields.

	The grid is rebuilt when an obstacle receives or loses the configured tag.
	Characters first use a direct grid line and only request a flow field when an
	obstacle blocks the target. Flow fields are cached by target key.

	@class SimulatedCharacterNavigationGrid
]=]

const CollectionService = game:GetService("CollectionService")

const require = require("../../Loader").load()

const Maid = require("Maid")
const SimulatedCharacterConstants = require("SimulatedCharacterConstants")
const SimulatedCharacterTypes = require("SimulatedCharacterTypes")

type FlowField = {
	targetIndex: number,
	nextByIndex: { [number]: number },
	builtAt: number,
	lastUsedAt: number,
}

const NEIGHBORS = table.freeze({
	{ x = 1, z = 0, cost = 10 },
	{ x = -1, z = 0, cost = 10 },
	{ x = 0, z = 1, cost = 10 },
	{ x = 0, z = -1, cost = 10 },
	{ x = 1, z = 1, cost = 14 },
	{ x = 1, z = -1, cost = 14 },
	{ x = -1, z = 1, cost = 14 },
	{ x = -1, z = -1, cost = 14 },
})

const function heapPush(indices: { number }, costs: { number }, index: number, cost: number)
	local cursor = #indices + 1
	while cursor > 1 do
		const parent = math.floor(cursor * 0.5)
		if costs[parent] <= cost then
			break
		end

		indices[cursor] = indices[parent]
		costs[cursor] = costs[parent]
		cursor = parent
	end

	indices[cursor] = index
	costs[cursor] = cost
end

const function heapPop(indices: { number }, costs: { number }): (number?, number?)
	const count = #indices
	if count == 0 then
		return nil, nil
	end

	const rootIndex = indices[1]
	const rootCost = costs[1]
	const lastIndex = indices[count]
	const lastCost = costs[count]
	indices[count] = nil
	costs[count] = nil

	if count > 1 then
		local cursor = 1
		while true do
			const left = cursor * 2
			if left >= count then
				break
			end

			const right = left + 1
			local child = left
			if right < count and costs[right] < costs[left] then
				child = right
			end
			if costs[child] >= lastCost then
				break
			end

			indices[cursor] = indices[child]
			costs[cursor] = costs[child]
			cursor = child
		end

		indices[cursor] = lastIndex
		costs[cursor] = lastCost
	end

	return rootIndex, rootCost
end

const SimulatedCharacterNavigationGrid = {}
SimulatedCharacterNavigationGrid.ClassName = "SimulatedCharacterNavigationGrid"
SimulatedCharacterNavigationGrid.__index = SimulatedCharacterNavigationGrid

export type SimulatedCharacterNavigationGrid = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_min: Vector2,
		_max: Vector2,
		_cellSize: number,
		_agentRadius: number,
		_obstacleTag: string,
		_width: number,
		_height: number,
		_walkable: { boolean },
		_flowFields: { [any]: FlowField },
		_costScratch: { [number]: number },
		_heapIndices: { number },
		_heapCosts: { number },
		_lastFlowFieldPruneAt: number,
		_needsRebuild: boolean,
	},
	SimulatedCharacterNavigationGrid
))

--[=[
	Constructs a navigation grid from explicit X/Z bounds.

	@within SimulatedCharacterNavigationGrid
	@param config NavigationConfig
	@return SimulatedCharacterNavigationGrid
]=]
function SimulatedCharacterNavigationGrid.new(
	config: SimulatedCharacterTypes.NavigationConfig
): SimulatedCharacterNavigationGrid
	assert(type(config) == "table", "Bad config")
	assert(typeof(config.Min) == "Vector2", "Bad config.Min")
	assert(typeof(config.Max) == "Vector2", "Bad config.Max")
	assert(config.Max.X > config.Min.X and config.Max.Y > config.Min.Y, "Navigation bounds must have area")
	assert(config.CellSize == nil or config.CellSize > 0, "Bad config.CellSize")
	assert(config.AgentRadius == nil or config.AgentRadius >= 0, "Bad config.AgentRadius")
	assert(config.ObstacleTag == nil or type(config.ObstacleTag) == "string", "Bad config.ObstacleTag")

	const cellSize = config.CellSize or SimulatedCharacterConstants.DEFAULT_NAVIGATION_CELL_SIZE
	const self: SimulatedCharacterNavigationGrid = setmetatable({} :: any, SimulatedCharacterNavigationGrid)
	self._maid = Maid.new()
	self._min = config.Min
	self._max = config.Max
	self._cellSize = cellSize
	self._agentRadius = config.AgentRadius or SimulatedCharacterConstants.DEFAULT_NAVIGATION_AGENT_RADIUS
	self._obstacleTag = config.ObstacleTag or SimulatedCharacterConstants.DEFAULT_OBSTACLE_TAG
	self._width = math.max(1, math.ceil((config.Max.X - config.Min.X) / cellSize))
	self._height = math.max(1, math.ceil((config.Max.Y - config.Min.Y) / cellSize))
	self._walkable = table.create(self._width * self._height, true)
	self._flowFields = {}
	self._costScratch = {}
	self._heapIndices = {}
	self._heapCosts = {}
	self._lastFlowFieldPruneAt = os.clock()
	self._needsRebuild = true

	self._maid:Add(CollectionService:GetInstanceAddedSignal(self._obstacleTag):Connect(function()
		self._needsRebuild = true
	end))
	self._maid:Add(CollectionService:GetInstanceRemovedSignal(self._obstacleTag):Connect(function()
		self._needsRebuild = true
	end))

	self:Rebuild()
	return self
end

--[=[
	Rebuilds occupied cells from every tagged obstacle.

	@within SimulatedCharacterNavigationGrid
]=]
function SimulatedCharacterNavigationGrid.Rebuild(self: SimulatedCharacterNavigationGrid)
	table.clear(self._walkable)
	for index = 1, self._width * self._height do
		self._walkable[index] = true
	end

	for _, obstacle in CollectionService:GetTagged(self._obstacleTag) do
		if obstacle:IsDescendantOf(workspace) then
			local obstacleCFrame, obstacleSize = self:_getObstacleBounds(obstacle)
			if obstacleCFrame and obstacleSize then
				self:_markObstacle(obstacleCFrame, obstacleSize)
			end
		end
	end

	table.clear(self._flowFields)
	self._needsRebuild = false
end

--[=[
	Returns a normalized X/Z movement direction toward a target. The target key
	shares one cached flow field between all characters chasing that target.

	@within SimulatedCharacterNavigationGrid
	@param position Vector2
	@param targetKey any
	@param targetPosition Vector2
	@return Vector2?
]=]
function SimulatedCharacterNavigationGrid.GetDirection(
	self: SimulatedCharacterNavigationGrid,
	position: Vector2,
	targetKey: any,
	targetPosition: Vector2
): Vector2?
	assert(typeof(position) == "Vector2", "Bad position")
	assert(targetKey ~= nil, "No targetKey")
	assert(typeof(targetPosition) == "Vector2", "Bad targetPosition")
	self:_ensureCurrent()

	const delta = targetPosition - position
	if delta.Magnitude < 1e-4 then
		return Vector2.zero
	end
	if self:_isSegmentWalkable(position, targetPosition) then
		return delta.Unit
	end

	const targetIndex = self:_findNearestWalkableIndex(targetPosition)
	const positionIndex = self:_findNearestWalkableIndex(position)
	if not targetIndex or not positionIndex then
		return nil
	end

	const now = os.clock()
	self:_pruneFlowFields(now)
	local flowField = self._flowFields[targetKey]
	if
		not flowField
		or (
			flowField.targetIndex ~= targetIndex
			and now - flowField.builtAt >= SimulatedCharacterConstants.DEFAULT_FLOW_FIELD_REFRESH
		)
	then
		flowField = self:_buildFlowField(targetIndex, now, flowField)
		self._flowFields[targetKey] = flowField
	end
	flowField.lastUsedAt = now

	const nextIndex = flowField.nextByIndex[positionIndex]
	if not nextIndex then
		return nil
	end

	const nextPosition = self:_indexToWorld(nextIndex)
	const nextDelta = nextPosition - position
	return if nextDelta.Magnitude > 1e-4 then nextDelta.Unit else delta.Unit
end

--[=[
	Returns whether a position is inside a currently walkable cell.

	@within SimulatedCharacterNavigationGrid
	@param position Vector2
	@return boolean
]=]
function SimulatedCharacterNavigationGrid.IsWalkable(self: SimulatedCharacterNavigationGrid, position: Vector2): boolean
	self:_ensureCurrent()
	local x, z = self:_worldToCell(position)
	const index = if x and z then self:_cellToIndex(x, z) else nil
	return index ~= nil and self._walkable[index] == true
end

--[=[
	Returns whether a movement segment remains inside walkable cells.

	@within SimulatedCharacterNavigationGrid
	@param from Vector2
	@param to Vector2
	@return boolean
]=]
function SimulatedCharacterNavigationGrid.CanMove(
	self: SimulatedCharacterNavigationGrid,
	from: Vector2,
	to: Vector2
): boolean
	self:_ensureCurrent()
	return self:_isSegmentWalkable(from, to)
end

function SimulatedCharacterNavigationGrid._ensureCurrent(self: SimulatedCharacterNavigationGrid)
	if self._needsRebuild then
		self:Rebuild()
	end
end

function SimulatedCharacterNavigationGrid._pruneFlowFields(self: SimulatedCharacterNavigationGrid, now: number)
	if now - self._lastFlowFieldPruneAt < SimulatedCharacterConstants.DEFAULT_FLOW_FIELD_PRUNE_INTERVAL then
		return
	end

	self._lastFlowFieldPruneAt = now
	for targetKey, flowField in self._flowFields do
		if now - flowField.lastUsedAt >= SimulatedCharacterConstants.DEFAULT_FLOW_FIELD_LIFETIME then
			self._flowFields[targetKey] = nil
		end
	end
end

function SimulatedCharacterNavigationGrid._getObstacleBounds(
	_self: SimulatedCharacterNavigationGrid,
	obstacle: Instance
): (CFrame?, Vector3?)
	if obstacle:IsA("BasePart") then
		return obstacle.CFrame, obstacle.Size
	elseif obstacle:IsA("Model") then
		return obstacle:GetBoundingBox()
	end
	return nil, nil
end

function SimulatedCharacterNavigationGrid._markObstacle(
	self: SimulatedCharacterNavigationGrid,
	obstacleCFrame: CFrame,
	obstacleSize: Vector3
)
	const halfSize = obstacleSize * 0.5
	const xVector = obstacleCFrame.XVector
	const yVector = obstacleCFrame.YVector
	const zVector = obstacleCFrame.ZVector
	const extentX = math.abs(xVector.X) * halfSize.X
		+ math.abs(yVector.X) * halfSize.Y
		+ math.abs(zVector.X) * halfSize.Z
		+ self._agentRadius
	const extentZ = math.abs(xVector.Z) * halfSize.X
		+ math.abs(yVector.Z) * halfSize.Y
		+ math.abs(zVector.Z) * halfSize.Z
		+ self._agentRadius
	const center = obstacleCFrame.Position

	const minX = math.max(0, math.floor((center.X - extentX - self._min.X) / self._cellSize))
	const maxX = math.min(self._width - 1, math.floor((center.X + extentX - self._min.X) / self._cellSize))
	const minZ = math.max(0, math.floor((center.Z - extentZ - self._min.Y) / self._cellSize))
	const maxZ = math.min(self._height - 1, math.floor((center.Z + extentZ - self._min.Y) / self._cellSize))

	for z = minZ, maxZ do
		for x = minX, maxX do
			self._walkable[self:_cellToIndex(x, z)] = false
		end
	end
end

function SimulatedCharacterNavigationGrid._worldToCell(
	self: SimulatedCharacterNavigationGrid,
	position: Vector2
): (number?, number?)
	const x = math.floor((position.X - self._min.X) / self._cellSize)
	const z = math.floor((position.Y - self._min.Y) / self._cellSize)
	if x < 0 or x >= self._width or z < 0 or z >= self._height then
		return nil, nil
	end
	return x, z
end

function SimulatedCharacterNavigationGrid._cellToIndex(
	self: SimulatedCharacterNavigationGrid,
	x: number,
	z: number
): number
	return x + z * self._width + 1
end

function SimulatedCharacterNavigationGrid._indexToCell(
	self: SimulatedCharacterNavigationGrid,
	index: number
): (number, number)
	const zeroIndex = index - 1
	const z = math.floor(zeroIndex / self._width)
	return zeroIndex - z * self._width, z
end

function SimulatedCharacterNavigationGrid._indexToWorld(self: SimulatedCharacterNavigationGrid, index: number): Vector2
	local x, z = self:_indexToCell(index)
	return Vector2.new(self._min.X + (x + 0.5) * self._cellSize, self._min.Y + (z + 0.5) * self._cellSize)
end

function SimulatedCharacterNavigationGrid._findNearestWalkableIndex(
	self: SimulatedCharacterNavigationGrid,
	position: Vector2
): number?
	local centerX, centerZ = self:_worldToCell(position)
	if not centerX or not centerZ then
		return nil
	end

	for radius = 0, 4 do
		for z = centerZ - radius, centerZ + radius do
			for x = centerX - radius, centerX + radius do
				if
					x >= 0
					and x < self._width
					and z >= 0
					and z < self._height
					and (
						radius == 0
						or x == centerX - radius
						or x == centerX + radius
						or z == centerZ - radius
						or z == centerZ + radius
					)
				then
					const index = self:_cellToIndex(x, z)
					if self._walkable[index] then
						return index
					end
				end
			end
		end
	end

	return nil
end

function SimulatedCharacterNavigationGrid._isSegmentWalkable(
	self: SimulatedCharacterNavigationGrid,
	from: Vector2,
	to: Vector2
): boolean
	local fromX, fromZ = self:_worldToCell(from)
	local toX, toZ = self:_worldToCell(to)
	if not fromX or not fromZ or not toX or not toZ then
		return false
	end

	const steps = math.max(math.abs(toX - fromX), math.abs(toZ - fromZ))
	if steps == 0 then
		return self._walkable[self:_cellToIndex(fromX, fromZ)] == true
	end

	local previousX = fromX
	local previousZ = fromZ
	for step = 0, steps do
		const alpha = step / steps
		const x = math.floor(fromX + (toX - fromX) * alpha + 0.5)
		const z = math.floor(fromZ + (toZ - fromZ) * alpha + 0.5)
		if not self._walkable[self:_cellToIndex(x, z)] then
			return false
		end

		if x ~= previousX and z ~= previousZ then
			if
				not self._walkable[self:_cellToIndex(previousX, z)]
				or not self._walkable[self:_cellToIndex(x, previousZ)]
			then
				return false
			end
		end

		previousX = x
		previousZ = z
	end

	return true
end

function SimulatedCharacterNavigationGrid._buildFlowField(
	self: SimulatedCharacterNavigationGrid,
	targetIndex: number,
	now: number,
	existing: FlowField?
): FlowField
	const costByIndex = self._costScratch
	const nextByIndex = if existing then existing.nextByIndex else {}
	const heapIndices = self._heapIndices
	const heapCosts = self._heapCosts
	table.clear(costByIndex)
	table.clear(nextByIndex)
	table.clear(heapIndices)
	table.clear(heapCosts)
	costByIndex[targetIndex] = 0
	heapIndices[1] = targetIndex
	heapCosts[1] = 0

	while #heapIndices > 0 do
		local currentIndex, currentCost = heapPop(heapIndices, heapCosts)
		if not currentIndex or currentCost ~= costByIndex[currentIndex] then
			continue
		end

		local currentX, currentZ = self:_indexToCell(currentIndex)
		for _, neighbor in NEIGHBORS do
			const nextX = currentX + neighbor.x
			const nextZ = currentZ + neighbor.z
			if nextX < 0 or nextX >= self._width or nextZ < 0 or nextZ >= self._height then
				continue
			end

			const neighborIndex = self:_cellToIndex(nextX, nextZ)
			if not self._walkable[neighborIndex] then
				continue
			end
			if neighbor.x ~= 0 and neighbor.z ~= 0 then
				if
					not self._walkable[self:_cellToIndex(currentX + neighbor.x, currentZ)]
					or not self._walkable[self:_cellToIndex(currentX, currentZ + neighbor.z)]
				then
					continue
				end
			end

			const newCost = currentCost + neighbor.cost
			const oldCost = costByIndex[neighborIndex]
			if oldCost == nil or newCost < oldCost then
				costByIndex[neighborIndex] = newCost
				nextByIndex[neighborIndex] = currentIndex
				heapPush(heapIndices, heapCosts, neighborIndex, newCost)
			end
		end
	end

	if existing then
		existing.targetIndex = targetIndex
		existing.builtAt = now
		existing.lastUsedAt = now
		return existing
	end

	return {
		targetIndex = targetIndex,
		nextByIndex = nextByIndex,
		builtAt = now,
		lastUsedAt = now,
	}
end

function SimulatedCharacterNavigationGrid._getDebugPath(
	self: SimulatedCharacterNavigationGrid,
	position: Vector2,
	targetKey: any,
	targetPosition: Vector2
): { Vector2 }
	self:_ensureCurrent()
	const result = { position }
	if self:_isSegmentWalkable(position, targetPosition) then
		table.insert(result, targetPosition)
		return result
	end

	const targetIndex = self:_findNearestWalkableIndex(targetPosition)
	const positionIndex = self:_findNearestWalkableIndex(position)
	if not targetIndex or not positionIndex then
		return result
	end

	local flowField = self._flowFields[targetKey]
	if not flowField or flowField.targetIndex ~= targetIndex then
		self:GetDirection(position, targetKey, targetPosition)
		flowField = self._flowFields[targetKey]
	end
	if not flowField or flowField.targetIndex ~= targetIndex then
		return result
	end

	local currentIndex = positionIndex
	local currentPosition = self:_indexToWorld(currentIndex)
	local previousDirection: Vector2? = nil
	local reachedTarget = currentIndex == targetIndex
	for _ = 1, self._width * self._height do
		if reachedTarget then
			break
		end

		const nextIndex = flowField.nextByIndex[currentIndex]
		if not nextIndex then
			break
		end
		const nextPosition = self:_indexToWorld(nextIndex)
		const direction = (nextPosition - currentPosition).Unit
		if previousDirection and direction:Dot(previousDirection) < 0.999 then
			table.insert(result, currentPosition)
		end
		previousDirection = direction
		currentIndex = nextIndex
		currentPosition = nextPosition
		reachedTarget = currentIndex == targetIndex
	end

	if reachedTarget then
		table.insert(result, targetPosition)
	elseif (currentPosition - position).Magnitude > 1e-4 then
		table.insert(result, currentPosition)
	end
	return result
end

function SimulatedCharacterNavigationGrid.Destroy(self: SimulatedCharacterNavigationGrid)
	self._maid:DoCleaning()
	table.clear(self)
	setmetatable(self, nil)
end

return SimulatedCharacterNavigationGrid
