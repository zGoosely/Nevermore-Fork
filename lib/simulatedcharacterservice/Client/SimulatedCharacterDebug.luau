--!strict
--!optimize 2
--[=[
	Draw-based local visualization for SimulatedCharacterServiceClient.

	@class SimulatedCharacterDebug
]=]

const require = require("../../Loader").load()

const Draw = require("Draw")
const Maid = require("Maid")
const SimulatedCharacterTypes = require("SimulatedCharacterTypes")
const SimulatedCharacterUtils = require("SimulatedCharacterUtils")

const RING_SEGMENTS = 12
const LINE_DIAMETER = 0.15
const NAVIGATION_Y = 0.15

const HITBOX_COLOR = Color3.fromRGB(255, 75, 75)
const CULL_RANGE_COLOR = Color3.fromRGB(210, 210, 210)
const NETWORK_RANGE_COLOR = Color3.fromRGB(70, 210, 255)
const FLOCK_RANGE_COLOR = Color3.fromRGB(235, 90, 255)
const STOPPING_RANGE_COLOR = Color3.fromRGB(255, 220, 70)
const PATH_COLOR = Color3.fromRGB(80, 255, 125)
const VELOCITY_COLOR = Color3.fromRGB(255, 145, 55)
const NAVIGATION_COLOR = Color3.fromRGB(80, 130, 255)

type CharacterVisual = {
	folder: Folder,
	hitbox: BasePart,
	cullRange: { BasePart },
	networkRange: { BasePart },
	flockRange: { BasePart },
	stoppingRange: { BasePart },
	path: { BasePart },
	velocity: BasePart?,
	generation: number,
}

const function setRayVisible(ray: BasePart, visible: boolean)
	ray.Transparency = if visible then 0.5 else 1
	const adornment = ray:FindFirstChildWhichIsA("CylinderHandleAdornment")
	if adornment then
		adornment.Transparency = if visible then 0.25 else 1
	end
end

const function hideRays(rays: { BasePart }, firstIndex: number?)
	for index = firstIndex or 1, #rays do
		setRayVisible(rays[index], false)
	end
end

const function updateRay(
	rays: { BasePart },
	index: number,
	startPosition: Vector3,
	endPosition: Vector3,
	color: Color3,
	parent: Instance
)
	local ray = rays[index]
	if not ray then
		ray = Draw.line(startPosition, endPosition, color, parent, LINE_DIAMETER)
		rays[index] = ray
	else
		Draw.updateRay(ray, Ray.new(startPosition, endPosition - startPosition), color, LINE_DIAMETER)
	end
	setRayVisible(ray, true)
end

const function updateRing(rays: { BasePart }, center: Vector3, radius: number, color: Color3, parent: Instance)
	if radius <= 0 then
		hideRays(rays)
		return
	end

	for index = 1, RING_SEGMENTS do
		const firstAngle = (index - 1) / RING_SEGMENTS * 2 * math.pi
		const secondAngle = index / RING_SEGMENTS * 2 * math.pi
		const startPosition = center + Vector3.new(math.cos(firstAngle) * radius, 0, math.sin(firstAngle) * radius)
		const endPosition = center + Vector3.new(math.cos(secondAngle) * radius, 0, math.sin(secondAngle) * radius)
		updateRay(rays, index, startPosition, endPosition, color, parent)
	end
end

const function updatePath(
	rays: { BasePart },
	points: { SimulatedCharacterTypes.NetworkDebugPoint },
	y: number,
	parent: Instance
)
	const segmentCount = math.max(0, #points - 1)
	for index = 1, segmentCount do
		const first = points[index]
		const second = points[index + 1]
		updateRay(rays, index, Vector3.new(first.x, y, first.z), Vector3.new(second.x, y, second.z), PATH_COLOR, parent)
	end
	hideRays(rays, segmentCount + 1)
end

const SimulatedCharacterDebug = {}
SimulatedCharacterDebug.ClassName = "SimulatedCharacterDebug"
SimulatedCharacterDebug.__index = SimulatedCharacterDebug

export type SimulatedCharacterDebug = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_service: any,
		_folder: Folder,
		_navigationFolder: Folder?,
		_navigationKey: string,
		_visuals: { [number]: CharacterVisual },
		_generation: number,
	},
	SimulatedCharacterDebug
))

function SimulatedCharacterDebug.new(service: any): SimulatedCharacterDebug
	const self: SimulatedCharacterDebug = setmetatable({} :: any, SimulatedCharacterDebug)
	self._maid = Maid.new()
	self._service = service
	self._navigationFolder = nil
	self._navigationKey = ""
	self._visuals = {}
	self._generation = 0

	const folder = Instance.new("Folder")
	folder.Name = "SimulatedCharacterDebug"
	folder.Parent = workspace
	self._folder = self._maid:Add(folder)
	return self
end

function SimulatedCharacterDebug._applySnapshot(
	self: SimulatedCharacterDebug,
	snapshot: SimulatedCharacterTypes.NetworkDebugSnapshot
)
	self:_updateNavigationBounds(snapshot)
	self._generation += 1
	const generation = self._generation
	for _, debugCharacter in snapshot.characters do
		const character = self._service._charactersById[debugCharacter.id]
		if not character then
			continue
		end

		local visual = self._visuals[debugCharacter.id]
		if not visual then
			visual = self:_createCharacterVisual(character, debugCharacter)
			self._visuals[debugCharacter.id] = visual
		end
		visual.generation = generation
		self:_updateCharacterVisual(character, debugCharacter, visual)
	end

	for id, visual in self._visuals do
		if visual.generation ~= generation then
			visual.folder:Destroy()
			self._visuals[id] = nil
		end
	end
end

function SimulatedCharacterDebug._createCharacterVisual(
	self: SimulatedCharacterDebug,
	character: any,
	debugCharacter: SimulatedCharacterTypes.NetworkDebugCharacter
): CharacterVisual
	const folder = Instance.new("Folder")
	folder.Name = `Character_{character._id}`
	folder.Parent = self._folder

	const definition = character._definition
	const hitboxSize =
		Vector3.new(definition.hitboxRadius * 2, debugCharacter.hitboxHeight, definition.hitboxRadius * 2)
	const hitbox = Draw.box(self:_getCharacterCFrame(character), hitboxSize, HITBOX_COLOR)
	hitbox.Name = "Hitbox"
	hitbox.Parent = folder
	return {
		folder = folder,
		hitbox = hitbox,
		cullRange = {},
		networkRange = {},
		flockRange = {},
		stoppingRange = {},
		path = {},
		velocity = nil,
		generation = 0,
	}
end

function SimulatedCharacterDebug._updateCharacterVisual(
	self: SimulatedCharacterDebug,
	character: any,
	debugCharacter: SimulatedCharacterTypes.NetworkDebugCharacter,
	visual: CharacterVisual
)
	const definition = character._definition
	const cframe = self:_getCharacterCFrame(character)
	const position = cframe.Position
	const hitboxSize =
		Vector3.new(definition.hitboxRadius * 2, debugCharacter.hitboxHeight, definition.hitboxRadius * 2)
	visual.hitbox.CFrame = cframe
	visual.hitbox.Size = hitboxSize
	const hitboxAdornment = visual.hitbox:FindFirstChildWhichIsA("BoxHandleAdornment")
	if hitboxAdornment then
		hitboxAdornment.Size = hitboxSize
	end

	const ringCenter = position + Vector3.new(0, hitboxSize.Y * 0.5 + 0.15, 0)
	updateRing(
		visual.cullRange,
		ringCenter,
		definition.cullDistance + definition.hitboxRadius,
		CULL_RANGE_COLOR,
		visual.folder
	)
	updateRing(
		visual.networkRange,
		ringCenter + Vector3.new(0, 0.15, 0),
		debugCharacter.replicationDistance + definition.hitboxRadius,
		NETWORK_RANGE_COLOR,
		visual.folder
	)
	if debugCharacter.hasFlock then
		updateRing(
			visual.flockRange,
			ringCenter + Vector3.new(0, 0.3, 0),
			debugCharacter.flockNeighborRadius,
			FLOCK_RANGE_COLOR,
			visual.folder
		)
	else
		hideRays(visual.flockRange)
	end

	updatePath(visual.path, debugCharacter.path, position.Y + hitboxSize.Y * 0.5 + 0.45, visual.folder)
	if debugCharacter.hasTarget then
		updateRing(
			visual.stoppingRange,
			Vector3.new(debugCharacter.targetX, ringCenter.Y + 0.3, debugCharacter.targetZ),
			debugCharacter.stoppingDistance,
			STOPPING_RANGE_COLOR,
			visual.folder
		)
	else
		hideRays(visual.stoppingRange)
	end

	const state = character._currentState
	const velocity = Vector2.new(state.velocityX, state.velocityZ)
	const velocityMagnitude = velocity.Magnitude
	if velocityMagnitude > 1e-4 then
		const direction = velocity / velocityMagnitude
		const startPosition = position + Vector3.new(0, hitboxSize.Y * 0.5 + 0.75, 0)
		const endPosition = startPosition + Vector3.new(direction.X, 0, direction.Y) * 5
		const velocityRay = visual.velocity
		if velocityRay then
			Draw.updateRay(
				velocityRay,
				Ray.new(startPosition, endPosition - startPosition),
				VELOCITY_COLOR,
				LINE_DIAMETER * 1.5
			)
			setRayVisible(velocityRay, true)
		else
			const createdVelocityRay =
				Draw.line(startPosition, endPosition, VELOCITY_COLOR, visual.folder, LINE_DIAMETER * 1.5)
			visual.velocity = createdVelocityRay
			setRayVisible(createdVelocityRay, true)
		end
	else
		const velocityRay = visual.velocity
		if velocityRay then
			setRayVisible(velocityRay, false)
		end
	end
end

function SimulatedCharacterDebug._getCharacterCFrame(_self: SimulatedCharacterDebug, character: any): CFrame
	if character._renderIndex ~= 0 then
		return character:GetRenderCFrame()
	end

	const state = character._currentState
	return SimulatedCharacterUtils.toCFrame(state.x, state.z, state.groundY, state.height, state.yaw)
end

function SimulatedCharacterDebug._updateNavigationBounds(
	self: SimulatedCharacterDebug,
	snapshot: SimulatedCharacterTypes.NetworkDebugSnapshot
)
	const navigationKey = if snapshot.hasNavigation
		then `{snapshot.navigationMinX}:{snapshot.navigationMinZ}:{snapshot.navigationMaxX}:{snapshot.navigationMaxZ}`
		else ""
	if self._navigationKey == navigationKey then
		return
	end
	self._navigationKey = navigationKey
	if self._navigationFolder then
		self._navigationFolder:Destroy()
		self._navigationFolder = nil
	end
	if not snapshot.hasNavigation then
		return
	end

	const folder = Instance.new("Folder")
	folder.Name = "NavigationBounds"
	folder.Parent = self._folder
	self._navigationFolder = folder
	const corners = {
		Vector3.new(snapshot.navigationMinX, NAVIGATION_Y, snapshot.navigationMinZ),
		Vector3.new(snapshot.navigationMaxX, NAVIGATION_Y, snapshot.navigationMinZ),
		Vector3.new(snapshot.navigationMaxX, NAVIGATION_Y, snapshot.navigationMaxZ),
		Vector3.new(snapshot.navigationMinX, NAVIGATION_Y, snapshot.navigationMaxZ),
	}
	for index = 1, 4 do
		Draw.line(corners[index], corners[index % 4 + 1], NAVIGATION_COLOR, folder, LINE_DIAMETER * 2)
	end
end

function SimulatedCharacterDebug.Destroy(self: SimulatedCharacterDebug)
	for _, visual in self._visuals do
		visual.folder:Destroy()
	end
	table.clear(self._visuals)
	self._maid:DoCleaning()
	table.clear(self)
	setmetatable(self, nil)
end

return SimulatedCharacterDebug
