--!strict
--!optimize 2
--[=[
	Maintains lightweight server-side flock groups and computes planar crowd
	steering without allocating per simulation step.

	@class SimulatedCharacterFlocking
]=]

const require = require("../../Loader").load()

const Maid = require("Maid")
const SimulatedCharacterConstants = require("SimulatedCharacterConstants")
const TableUtils = require("TableUtils")

const OVERLAP_SOLVER_ITERATIONS = 4
const OVERLAP_EPSILON = 1e-3

type FlockCharacterDefinition = {
	FlockGroup: string,
	HitboxRadius: number,
	FlockNeighborRadius: number,
	FlockSeparationPadding: number,
	FlockSeparationWeight: number,
	FlockAlignmentWeight: number,
	FlockCohesionWeight: number,
	FlockMaxSteering: number,
}

type FlockCharacter = {
	_id: number,
	_flockIndex: number,
	_flockSeparation: Vector2,
	_flockSteering: Vector2,
	_definition: FlockCharacterDefinition,
	_mode: number,
	_position: Vector2,
	_velocity: Vector2,
	_simulationRate: number,
}

type FlockGroup = {
	characters: { FlockCharacter },
}

const SimulatedCharacterFlocking = {}
SimulatedCharacterFlocking.ClassName = "SimulatedCharacterFlocking"
SimulatedCharacterFlocking.__index = SimulatedCharacterFlocking

export type SimulatedCharacterFlocking = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_groups: { [string]: FlockGroup },
	},
	SimulatedCharacterFlocking
))

function SimulatedCharacterFlocking.new(): SimulatedCharacterFlocking
	const self: SimulatedCharacterFlocking = setmetatable({} :: any, SimulatedCharacterFlocking)
	self._maid = Maid.new()
	self._groups = {}
	return self
end

--[=[
	Adds an internal simulated character to its configured flock group.

	@within SimulatedCharacterFlocking
	@param character FlockCharacter
]=]
function SimulatedCharacterFlocking.AddCharacter(self: SimulatedCharacterFlocking, character: FlockCharacter)
	const groupName = character._definition.FlockGroup
	character._flockIndex = 0
	character._flockSeparation = Vector2.zero
	character._flockSteering = Vector2.zero
	if groupName == "" then
		return
	end

	local group = self._groups[groupName]
	if not group then
		group = {
			characters = {},
		}
		self._groups[groupName] = group
	end

	character._flockIndex = #group.characters + 1
	table.insert(group.characters, character)
end

--[=[
	Removes an internal simulated character from its flock group.

	@within SimulatedCharacterFlocking
	@param character FlockCharacter
]=]
function SimulatedCharacterFlocking.RemoveCharacter(self: SimulatedCharacterFlocking, character: FlockCharacter)
	const groupName = character._definition.FlockGroup
	const index = character._flockIndex
	character._flockIndex = 0
	character._flockSeparation = Vector2.zero
	character._flockSteering = Vector2.zero
	if groupName == "" or index == 0 then
		return
	end

	const group = self._groups[groupName]
	if not group or group.characters[index] ~= character then
		return
	end

	const lastCharacter = group.characters[#group.characters]
	TableUtils.swapRemove(group.characters, index)
	if lastCharacter and lastCharacter ~= character then
		lastCharacter._flockIndex = index
	end
	if #group.characters == 0 then
		self._groups[groupName] = nil
	end
end

--[=[
	Computes the steering contribution for every active flock member.

	@within SimulatedCharacterFlocking
]=]
function SimulatedCharacterFlocking.Step(self: SimulatedCharacterFlocking)
	for _, group in self._groups do
		const characters = group.characters
		for _, character in characters do
			character._flockSeparation = Vector2.zero
			character._flockSteering = Vector2.zero
			if character._mode ~= SimulatedCharacterConstants.Modes.KINEMATIC then
				continue
			end

			const position = character._position
			const neighborRadiusSquared = character._definition.FlockNeighborRadius ^ 2
			local separation = Vector2.zero
			local alignment = Vector2.zero
			local center = Vector2.zero
			local neighborCount = 0
			for _, neighbor in characters do
				if neighbor == character or neighbor._mode ~= SimulatedCharacterConstants.Modes.KINEMATIC then
					continue
				end

				local delta = neighbor._position - position
				const distanceSquared = delta:Dot(delta)
				if distanceSquared > neighborRadiusSquared then
					continue
				end

				neighborCount += 1
				alignment += neighbor._velocity * (neighbor._simulationRate or 1)
				center += neighbor._position
				const separationDistance = character._definition.HitboxRadius
					+ neighbor._definition.HitboxRadius
					+ math.max(
						character._definition.FlockSeparationPadding,
						neighbor._definition.FlockSeparationPadding
					)
				if distanceSquared > 1e-6 then
					const distance = math.sqrt(distanceSquared)
					if distance < separationDistance then
						separation -= delta / distance * (1 - distance / separationDistance)
					end
				else
					const lowerId = math.min(character._id, neighbor._id)
					const upperId = math.max(character._id, neighbor._id)
					const angle = (lowerId * 97 + upperId * 57) % 6283 / 1000
					delta = Vector2.new(math.cos(angle), math.sin(angle))
					separation += if character._id == lowerId then delta else -delta
				end
			end

			if neighborCount == 0 then
				continue
			end

			const separationMagnitude = separation.Magnitude
			if separationMagnitude > 1 then
				separation /= separationMagnitude
			end
			const weightedSeparation = separation * character._definition.FlockSeparationWeight
			local steering = weightedSeparation
			const alignmentMagnitude = alignment.Magnitude
			if alignmentMagnitude > 1e-4 then
				steering += alignment / alignmentMagnitude * character._definition.FlockAlignmentWeight
			end
			const cohesionDelta = center / neighborCount - position
			const cohesionMagnitude = cohesionDelta.Magnitude
			if cohesionMagnitude > 1e-4 then
				steering += cohesionDelta / cohesionMagnitude * character._definition.FlockCohesionWeight
			end

			const steeringMagnitude = steering.Magnitude
			if steeringMagnitude > character._definition.FlockMaxSteering then
				steering = steering / steeringMagnitude * character._definition.FlockMaxSteering
			end
			character._flockSeparation = weightedSeparation
			character._flockSteering = steering
		end
	end
end

function SimulatedCharacterFlocking._resolveOverlaps(self: SimulatedCharacterFlocking, navigation: any?)
	for _, group in self._groups do
		const characters = group.characters
		if #characters < 2 then
			continue
		end

		for _ = 1, OVERLAP_SOLVER_ITERATIONS do
			local resolvedAny = false
			for firstIndex = 1, #characters - 1 do
				const first = characters[firstIndex]
				if first._mode ~= SimulatedCharacterConstants.Modes.KINEMATIC then
					continue
				end

				for secondIndex = firstIndex + 1, #characters do
					const second = characters[secondIndex]
					if second._mode ~= SimulatedCharacterConstants.Modes.KINEMATIC then
						continue
					end

					const minimumDistance = first._definition.HitboxRadius
						+ second._definition.HitboxRadius
						+ math.max(first._definition.FlockSeparationPadding, second._definition.FlockSeparationPadding)
					local delta = second._position - first._position
					const distanceSquared = delta:Dot(delta)
					if minimumDistance <= 0 or distanceSquared >= minimumDistance * minimumDistance then
						continue
					end

					local distance = 0
					if distanceSquared > 1e-6 then
						distance = math.sqrt(distanceSquared)
						delta /= distance
					else
						const lowerId = math.min(first._id, second._id)
						const upperId = math.max(first._id, second._id)
						const angle = (lowerId * 97 + upperId * 57) % 6283 / 1000
						delta = Vector2.new(math.cos(angle), math.sin(angle))
						if first._id > second._id then
							delta = -delta
						end
					end

					const correctionDistance = minimumDistance - distance + OVERLAP_EPSILON
					const firstCanMove = (first._simulationRate or 1) > 0
					const secondCanMove = (second._simulationRate or 1) > 0
					if firstCanMove and secondCanMove then
						const correction = delta * (correctionDistance * 0.5)
						const firstPosition = first._position - correction
						const secondPosition = second._position + correction
						const firstPositionValid = not navigation or navigation:CanMove(first._position, firstPosition)
						const secondPositionValid = not navigation
							or navigation:CanMove(second._position, secondPosition)
						if firstPositionValid and secondPositionValid then
							first._position = firstPosition
							second._position = secondPosition
							resolvedAny = true
							continue
						end
					end

					if firstCanMove then
						const firstPosition = first._position - delta * correctionDistance
						if not navigation or navigation:CanMove(first._position, firstPosition) then
							first._position = firstPosition
							resolvedAny = true
							continue
						end
					end
					if secondCanMove then
						const secondPosition = second._position + delta * correctionDistance
						if not navigation or navigation:CanMove(second._position, secondPosition) then
							second._position = secondPosition
							resolvedAny = true
						end
					end
				end
			end

			if not resolvedAny then
				break
			end
		end
	end
end

function SimulatedCharacterFlocking.Destroy(self: SimulatedCharacterFlocking)
	for _, group in self._groups do
		for _, character in group.characters do
			character._flockIndex = 0
			character._flockSeparation = Vector2.zero
			character._flockSteering = Vector2.zero
		end
	end
	self._maid:DoCleaning()
	table.clear(self)
	setmetatable(self, nil)
end

return SimulatedCharacterFlocking
