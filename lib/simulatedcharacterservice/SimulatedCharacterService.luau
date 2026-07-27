--!strict
--!optimize 2
--[=[
	Runs lightweight, server-authoritative simulated characters on a flat X/Z
	plane and replicates their render state to clients.

	@server
	@class SimulatedCharacterService
]=]

const CollectionService = game:GetService("CollectionService")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const require = require("../Loader").load()

const Maid = require("Maid")
const RandomUtils = require("RandomUtils")
const ServiceBag = require("ServiceBag")
const SimulatedCharacter = require("SimulatedCharacter")
const SimulatedCharacterConstants = require("SimulatedCharacterConstants")
const SimulatedCharacterFlocking = require("SimulatedCharacterFlocking")
const SimulatedCharacterNavigationGrid = require("SimulatedCharacterNavigationGrid")
const SimulatedCharacterNetwork = require("SimulatedCharacterNetwork")
const SimulatedCharacterSpatialHash = require("SimulatedCharacterSpatialHash")
const SimulatedCharacterStateCodec = require("SimulatedCharacterStateCodec")
const SimulatedCharacterTemplateProvider = require("SimulatedCharacterTemplateProvider")
const SimulatedCharacterTargetingMode = require("SimulatedCharacterTargetingMode")
const SimulatedCharacterTypes = require("SimulatedCharacterTypes")
const SimulatedCharacterUtils = require("SimulatedCharacterUtils")
const SimulatedCharacterVariantSelectionMode = require("SimulatedCharacterVariantSelectionMode")
const TableUtils = require("TableUtils")
const TimeSyncService = require("TimeSyncService")
const WeightedRandomChooser = require("WeightedRandomChooser")

const DEBUG_REQUEST_COOLDOWN = 0.15

const SimulatedCharacterService = {}
SimulatedCharacterService.ServiceName = "SimulatedCharacterService"
SimulatedCharacterService.ServerOnly = true

export type SimulatedCharacterService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_timeSyncService: TimeSyncService.TimeSyncService,
		_clock: TimeSyncService.SyncedClock,
		_templateProvider: any,
		_templateContainer: Folder?,
		_definitions: { [string]: SimulatedCharacterTypes.ResolvedCharacterDefinition },
		_variantChoosers: { [string]: any },
		_variantCursors: { [string]: number },
		_variantRandom: Random,
		_charactersById: { [number]: SimulatedCharacter.SimulatedCharacter },
		_characters: { SimulatedCharacter.SimulatedCharacter },
		_targetCandidates: { SimulatedCharacterTypes.TargetCandidate },
		_usesTargetCandidates: boolean,
		_flocking: SimulatedCharacterFlocking.SimulatedCharacterFlocking,
		_spatialHash: SimulatedCharacterSpatialHash.SimulatedCharacterSpatialHash,
		_networkInterestByPlayer: { [Player]: { [number]: boolean } },
		_lastDebugRequestByPlayer: { [Player]: number },
		_nextCharacterId: number,
		_navigation: SimulatedCharacterNavigationGrid.SimulatedCharacterNavigationGrid?,
		_simulationAccumulator: number,
		_snapshotAccumulator: number,
	},
	{} :: typeof({ __index = SimulatedCharacterService })
))

function SimulatedCharacterService.Init(self: SimulatedCharacterService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._definitions = {}
	self._variantChoosers = {}
	self._variantCursors = {}
	self._variantRandom = Random.new()
	self._charactersById = {}
	self._characters = {}
	self._targetCandidates = {}
	self._usesTargetCandidates = false
	self._flocking = self._maid:Add(SimulatedCharacterFlocking.new())
	self._spatialHash =
		self._maid:Add(SimulatedCharacterSpatialHash.new(SimulatedCharacterConstants.DEFAULT_SPATIAL_CELL_SIZE))
	self._networkInterestByPlayer = {}
	self._lastDebugRequestByPlayer = {}
	self._nextCharacterId = 1
	self._navigation = nil
	self._templateContainer = nil
	self._simulationAccumulator = 0
	self._snapshotAccumulator = 0
	self._timeSyncService = self._serviceBag:GetService(TimeSyncService)
	self._clock = assert(self._timeSyncService:GetSyncedClock(), "Server clock is unavailable")
	self._templateProvider = self._serviceBag:GetService(SimulatedCharacterTemplateProvider)

	SimulatedCharacterNetwork.queries.requestAnimationCatalogs.listen(function()
		return self:_getAnimationCatalogs()
	end)
	SimulatedCharacterNetwork.queries.requestInitialState.listen(function(_, player: Player?)
		if not player then
			return {}
		end
		return self:_getInitialState(player)
	end)
	SimulatedCharacterNetwork.packets.debugRequested.listen(function(_, player: Player?)
		if not player then
			return
		end

		const now = os.clock()
		const lastRequest = self._lastDebugRequestByPlayer[player]
		if lastRequest and now - lastRequest < DEBUG_REQUEST_COOLDOWN then
			return
		end
		self._lastDebugRequestByPlayer[player] = now
		self:_sendDebugSnapshot(player)
	end)
	self._maid:Add(Players.PlayerRemoving:Connect(function(player: Player)
		self._networkInterestByPlayer[player] = nil
		self._lastDebugRequestByPlayer[player] = nil
	end))
end

--[=[
	Points the service at an external replicated Folder containing character
	templates. The folder is tagged so the server and every client configure the
	same TemplateProvider automatically.

	The Folder should normally live in ReplicatedStorage. TemplateProvider hides
	the real models on the server and leaves only lightweight tombstones visible
	to clients until a model is requested.

	@within SimulatedCharacterService
	@param container Folder
]=]
function SimulatedCharacterService.SetTemplateContainer(self: SimulatedCharacterService, container: Folder)
	assert(typeof(container) == "Instance" and container:IsA("Folder"), "Bad container")
	if self._templateContainer == container then
		return
	end

	self._maid._templateContainerTag = nil
	self._templateContainer = container
	const wasTagged = CollectionService:HasTag(container, SimulatedCharacterConstants.TEMPLATE_CONTAINER_TAG)
	if not wasTagged then
		CollectionService:AddTag(container, SimulatedCharacterConstants.TEMPLATE_CONTAINER_TAG)
	end

	self._maid._templateContainerTag = function()
		if
			not wasTagged and CollectionService:HasTag(container, SimulatedCharacterConstants.TEMPLATE_CONTAINER_TAG)
		then
			CollectionService:RemoveTag(container, SimulatedCharacterConstants.TEMPLATE_CONTAINER_TAG)
		end
	end
end

function SimulatedCharacterService.Start(self: SimulatedCharacterService)
	self._simulationAccumulator = self._simulationAccumulator or 0
	self._snapshotAccumulator = self._snapshotAccumulator or 0
	self._maid:Add(RunService.Heartbeat:Connect(function(deltaTime: number)
		self:_step(deltaTime)
	end))
end

--[=[
	Configures explicit X/Z navigation bounds and the tagged obstacle grid.

	```lua
	SimulatedCharacterService:ConfigureNavigation({
		Min = Vector2.new(-512, -512),
		Max = Vector2.new(512, 512),
		CellSize = 4,
		ObstacleTag = "SimulatedCharacterObstacle",
	})
	```

	@within SimulatedCharacterService
	@param config NavigationConfig
]=]
function SimulatedCharacterService.ConfigureNavigation(
	self: SimulatedCharacterService,
	config: SimulatedCharacterTypes.NavigationConfig
)
	const navigation = SimulatedCharacterNavigationGrid.new(config)
	self._navigation = navigation
	self._maid._navigation = navigation
end

--[=[
	Rebuilds the navigation grid after moving or resizing tagged obstacles.

	@within SimulatedCharacterService
]=]
function SimulatedCharacterService.RebuildNavigation(self: SimulatedCharacterService)
	const navigation = self._navigation
	if navigation then
		navigation:Rebuild()
	end
end

--[=[
	Registers a character archetype.

	@within SimulatedCharacterService
	@param name string
	@param definition CharacterDefinition
	@return ResolvedCharacterDefinition
]=]
function SimulatedCharacterService.RegisterCharacter(
	self: SimulatedCharacterService,
	name: string,
	definition: SimulatedCharacterTypes.CharacterDefinition
): SimulatedCharacterTypes.ResolvedCharacterDefinition
	assert(type(name) == "string" and name ~= "", "Bad name")
	assert(self._definitions[name] == nil, `Character definition {name} is already registered`)
	const resolvedDefinition = SimulatedCharacterUtils.resolveDefinition(name, definition)
	self._definitions[name] = resolvedDefinition
	self._variantCursors[name] = 0
	if resolvedDefinition.TemplateSelectionMode == SimulatedCharacterVariantSelectionMode.WEIGHTED then
		const chooser = WeightedRandomChooser.new()
		for index, variant in resolvedDefinition.TemplateVariants do
			chooser:SetWeight(index, variant.Weight)
		end
		self._variantChoosers[name] = chooser
	end
	if resolvedDefinition.TargetingMode == SimulatedCharacterTargetingMode.NEAREST_PLAYER then
		self._usesTargetCandidates = true
	end
	if #resolvedDefinition.ActionAnimations > 0 then
		SimulatedCharacterNetwork.packets.animationCatalogChanged.sendToAll(
			self:_toAnimationCatalog(resolvedDefinition)
		)
	end
	return resolvedDefinition
end

--[=[
	Spawns a server-authoritative simulated character.

	@within SimulatedCharacterService
	@param definitionName string
	@param spawnData SpawnData?
	@return SimulatedCharacter
]=]
function SimulatedCharacterService.SpawnCharacter(
	self: SimulatedCharacterService,
	definitionName: string,
	spawnData: SimulatedCharacterTypes.SpawnData?
): SimulatedCharacter.SimulatedCharacter
	assert(type(definitionName) == "string", "Bad definitionName")
	const definition = assert(self._definitions[definitionName], `Unknown character definition {definitionName}`)
	const data = spawnData or {}
	assert(type(data) == "table", "Bad spawnData")
	assert(data.CFrame == nil or typeof(data.CFrame) == "CFrame", "Bad spawnData.CFrame")
	assert(data.Position == nil or typeof(data.Position) == "Vector2", "Bad spawnData.Position")
	assert(data.GroundY == nil or type(data.GroundY) == "number", "Bad spawnData.GroundY")
	assert(data.Yaw == nil or type(data.Yaw) == "number", "Bad spawnData.Yaw")
	assert(data.Ragdolled == nil or type(data.Ragdolled) == "boolean", "Bad spawnData.Ragdolled")

	local position = data.Position or Vector2.zero
	local groundY = data.GroundY or 0
	local yaw = data.Yaw or 0
	if data.CFrame then
		const cframe = data.CFrame
		const worldPosition = cframe.Position
		position = Vector2.new(worldPosition.X, worldPosition.Z)
		groundY = worldPosition.Y
		yaw = math.atan2(-cframe.LookVector.X, -cframe.LookVector.Z)
	end
	groundY = SimulatedCharacterUtils.resolveSpawnY(definition, groundY)

	const id = self._nextCharacterId
	assert(id <= 4_294_967_295, "Simulated character id space exhausted")
	self._nextCharacterId += 1

	const templateName = self:_selectTemplateName(definition)
	const character =
		SimulatedCharacter.new(self, id, definition, templateName, position, groundY, yaw, data.Ragdolled == true)
	character._listIndex = #self._characters + 1
	self._charactersById[id] = character
	table.insert(self._characters, character)
	self._flocking:AddCharacter(character)
	self._spatialHash:AddCharacter(character)

	SimulatedCharacterNetwork.packets.spawned.sendToAll(self:_toNetworkSpawn(character))
	for _, player in Players:GetPlayers() do
		const playerPosition = self:_getPlayerPosition(player)
		if playerPosition and self:_isCharacterInRange(character, playerPosition) then
			self:_getPlayerNetworkInterest(player)[id] = true
		end
	end
	return character
end

--[=[
	Removes a character by handle or numeric id. This method is idempotent.

	@within SimulatedCharacterService
	@param characterOrId SimulatedCharacter | number
]=]
function SimulatedCharacterService.RemoveCharacter(
	self: SimulatedCharacterService,
	characterOrId: SimulatedCharacter.SimulatedCharacter | number
)
	const character = if type(characterOrId) == "number"
		then self._charactersById[characterOrId]
		else characterOrId :: SimulatedCharacter.SimulatedCharacter
	if not character or self._charactersById[character._id] ~= character then
		return
	end

	const id = character._id
	self._charactersById[id] = nil
	self._flocking:RemoveCharacter(character)
	self._spatialHash:RemoveCharacter(character)
	for _, interest in self._networkInterestByPlayer do
		interest[id] = nil
	end
	const index = character._listIndex
	const lastCharacter = self._characters[#self._characters]
	TableUtils.swapRemove(self._characters, index)
	if lastCharacter and lastCharacter ~= character then
		lastCharacter._listIndex = index
	end

	SimulatedCharacterNetwork.packets.removed.sendToAll(id)
	character:_destroyInternal()
end

--[=[
	Returns a character by numeric id.

	@within SimulatedCharacterService
	@param id number
	@return SimulatedCharacter?
]=]
function SimulatedCharacterService.GetCharacter(
	self: SimulatedCharacterService,
	id: number
): SimulatedCharacter.SimulatedCharacter?
	return self._charactersById[id]
end

--[=[
	Returns a snapshot array of all current character handles.

	@within SimulatedCharacterService
	@return { SimulatedCharacter }
]=]
function SimulatedCharacterService.GetCharacters(
	self: SimulatedCharacterService
): { SimulatedCharacter.SimulatedCharacter }
	return table.clone(self._characters)
end

--[=[
	Returns simulated characters whose authoritative X/Z centers are within the
	given radius, ordered nearest-first. Vector3 Y is intentionally ignored.

	```lua
	const nearby = SimulatedCharacterService:Query(position, 50)
	const nearest = nearby[1]
	```

	@within SimulatedCharacterService
	@param position Vector2 | Vector3
	@param maxDistance number
	@return { SimulatedCharacter }
]=]
function SimulatedCharacterService.Query(
	self: SimulatedCharacterService,
	position: Vector2 | Vector3,
	maxDistance: number
): { SimulatedCharacter.SimulatedCharacter }
	assert(typeof(position) == "Vector2" or typeof(position) == "Vector3", "Bad position")
	assert(
		type(maxDistance) == "number" and maxDistance == maxDistance and maxDistance >= 0 and maxDistance < math.huge,
		"Bad maxDistance"
	)
	const planarPosition = SimulatedCharacterUtils.toPlanarPosition(position)
	assert(
		planarPosition.X == planarPosition.X
			and planarPosition.Y == planarPosition.Y
			and math.abs(planarPosition.X) < math.huge
			and math.abs(planarPosition.Y) < math.huge,
		"Bad position"
	)
	return self._spatialHash:Query(planarPosition, maxDistance) :: any
end

function SimulatedCharacterService._getTime(self: SimulatedCharacterService): number
	return self._clock:GetTime()
end

function SimulatedCharacterService._step(self: SimulatedCharacterService, deltaTime: number)
	const simulationStep = 1 / SimulatedCharacterConstants.DEFAULT_SIMULATION_RATE
	const snapshotStep = 1 / SimulatedCharacterConstants.DEFAULT_SNAPSHOT_RATE
	const boundedDelta = math.min(deltaTime, 0.25)
	local simulationAccumulator = self._simulationAccumulator + boundedDelta
	local snapshotAccumulator = self._snapshotAccumulator + boundedDelta

	local simulationCount = 0
	while simulationAccumulator >= simulationStep and simulationCount < 5 do
		simulationAccumulator -= simulationStep
		simulationCount += 1
		if self._usesTargetCandidates then
			self:_updateTargetCandidates()
		end
		self._flocking:Step()
		for _, character in self._characters do
			character:_step(simulationStep, self._navigation, self._targetCandidates)
		end
		self._flocking:_resolveOverlaps(self._navigation)
		self._spatialHash:UpdateCharacters(self._characters)
	end

	if snapshotAccumulator >= snapshotStep then
		snapshotAccumulator %= snapshotStep
		self:_sendSnapshot()
	end

	self._simulationAccumulator = simulationAccumulator
	self._snapshotAccumulator = snapshotAccumulator
end

function SimulatedCharacterService._updateTargetCandidates(self: SimulatedCharacterService)
	local count = 0
	for _, player in Players:GetPlayers() do
		const position = self:_getPlayerPosition(player)
		if not position then
			continue
		end

		count += 1
		local candidate = self._targetCandidates[count]
		if candidate then
			candidate.Player = player
			candidate.Position = position
		else
			candidate = {
				Player = player,
				Position = position,
			}
			self._targetCandidates[count] = candidate
		end
	end
	for index = #self._targetCandidates, count + 1, -1 do
		self._targetCandidates[index] = nil
	end
end

function SimulatedCharacterService._selectTemplateName(
	self: SimulatedCharacterService,
	definition: SimulatedCharacterTypes.ResolvedCharacterDefinition
): string
	const variants = definition.TemplateVariants
	if #variants == 1 then
		return variants[1].Name
	end

	const selectionMode = definition.TemplateSelectionMode
	if selectionMode == SimulatedCharacterVariantSelectionMode.WEIGHTED then
		const chooser = assert(self._variantChoosers[definition.Name], "Missing template variant chooser")
		const index = chooser:Choose(self._variantRandom)
		return variants[index].Name
	elseif selectionMode == SimulatedCharacterVariantSelectionMode.RANDOM then
		const variant = assert(RandomUtils.choice(variants, self._variantRandom), "No template variants")
		return variant.Name
	else
		const index = self._variantCursors[definition.Name] % #variants + 1
		self._variantCursors[definition.Name] = index
		return variants[index].Name
	end
end

function SimulatedCharacterService._sendSnapshot(self: SimulatedCharacterService)
	if #self._characters == 0 then
		return
	end

	const serverTime = self:_getTime()
	const networkStates = table.create(#self._characters)
	for index, character in self._characters do
		networkStates[index] = character:_getNetworkState()
	end

	for _, player in Players:GetPlayers() do
		const playerPosition = self:_getPlayerPosition(player)
		const interest = self:_getPlayerNetworkInterest(player)
		const states = table.create(#self._characters)
		for index, character in self._characters do
			const id = character._id
			const inRange = playerPosition ~= nil and self:_isCharacterInRange(character, playerPosition)
			if inRange then
				const wasInterested = interest[id] == true
				interest[id] = true
				table.insert(states, networkStates[index])
				if not wasInterested then
					self:_sendCurrentAnimation(character, player)
				end
			elseif interest[id] then
				interest[id] = nil
				SimulatedCharacterNetwork.packets.stateChanged.sendTo({
					serverTime = serverTime,
					state = networkStates[index],
				}, player)
			end
		end

		if #states > 0 then
			const originX, originZ, data = SimulatedCharacterStateCodec.encode(states)
			SimulatedCharacterNetwork.packets.snapshot.sendTo({
				serverTime = serverTime,
				originX = originX,
				originZ = originZ,
				data = data,
			}, player)
		end
	end
end

function SimulatedCharacterService._onCharacterStateChanged(
	self: SimulatedCharacterService,
	character: SimulatedCharacter.SimulatedCharacter
)
	if self._charactersById[character._id] == character then
		self._spatialHash:UpdateCharacter(character)
		const data = {
			serverTime = self:_getTime(),
			state = character:_getNetworkState(),
		}
		for _, player in Players:GetPlayers() do
			const interest = self:_getPlayerNetworkInterest(player)
			const wasInterested = interest[character._id] == true
			const playerPosition = self:_getPlayerPosition(player)
			const inRange = playerPosition ~= nil and self:_isCharacterInRange(character, playerPosition)
			if inRange or interest[character._id] then
				SimulatedCharacterNetwork.packets.stateChanged.sendTo(data, player)
			end
			if inRange then
				interest[character._id] = true
				if not wasInterested then
					self:_sendCurrentAnimation(character, player)
				end
			else
				interest[character._id] = nil
			end
		end
	end
end

function SimulatedCharacterService._onCharacterAnimationPlayed(
	self: SimulatedCharacterService,
	character: SimulatedCharacter.SimulatedCharacter,
	animation: SimulatedCharacterTypes.NetworkAnimationPlay
)
	if self._charactersById[character._id] ~= character then
		return
	end

	for _, player in Players:GetPlayers() do
		const interest = self:_getPlayerNetworkInterest(player)
		const playerPosition = self:_getPlayerPosition(player)
		const inRange = playerPosition ~= nil and self:_isCharacterInRange(character, playerPosition)
		if inRange or interest[character._id] then
			SimulatedCharacterNetwork.packets.animationPlayed.sendTo(animation, player)
		end
		if inRange then
			interest[character._id] = true
		end
	end
end

function SimulatedCharacterService._onCharacterAnimationStopped(
	self: SimulatedCharacterService,
	character: SimulatedCharacter.SimulatedCharacter,
	animation: SimulatedCharacterTypes.NetworkAnimationStop
)
	if self._charactersById[character._id] ~= character then
		return
	end

	for _, player in Players:GetPlayers() do
		const interest = self:_getPlayerNetworkInterest(player)
		const playerPosition = self:_getPlayerPosition(player)
		const inRange = playerPosition ~= nil and self:_isCharacterInRange(character, playerPosition)
		if inRange or interest[character._id] then
			SimulatedCharacterNetwork.packets.animationStopped.sendTo(animation, player)
		end
		if inRange then
			interest[character._id] = true
		end
	end
end

function SimulatedCharacterService._onCharacterSimulationRateChanged(
	self: SimulatedCharacterService,
	character: SimulatedCharacter.SimulatedCharacter
)
	if self._charactersById[character._id] ~= character then
		return
	end

	SimulatedCharacterNetwork.packets.simulationRateChanged.sendToAll({
		id = character._id,
		rate = character._simulationRate or 1,
	})
	self:_onCharacterStateChanged(character)
end

function SimulatedCharacterService._getPlayerNetworkInterest(
	self: SimulatedCharacterService,
	player: Player
): { [number]: boolean }
	local interest = self._networkInterestByPlayer[player]
	if not interest then
		interest = {}
		self._networkInterestByPlayer[player] = interest
	end
	return interest
end

function SimulatedCharacterService._getPlayerPosition(_self: SimulatedCharacterService, player: Player): Vector2?
	const playerCharacter = player.Character
	const root = playerCharacter and (playerCharacter:FindFirstChild("HumanoidRootPart") or playerCharacter.PrimaryPart)
	if root and root:IsA("BasePart") then
		return Vector2.new(root.Position.X, root.Position.Z)
	end
	return nil
end

function SimulatedCharacterService._isCharacterInRange(
	_self: SimulatedCharacterService,
	character: SimulatedCharacter.SimulatedCharacter,
	playerPosition: Vector2
): boolean
	const delta = character._position - playerPosition
	const distance = character._replicationDistance + character._definition.HitboxRadius
	return delta:Dot(delta) <= distance * distance
end

function SimulatedCharacterService._sendCurrentAnimation(
	_self: SimulatedCharacterService,
	character: SimulatedCharacter.SimulatedCharacter,
	player: Player
)
	const animation = character._activeAnimation
	if animation then
		SimulatedCharacterNetwork.packets.animationPlayed.sendTo(animation, player)
	end
end

function SimulatedCharacterService._sendDebugSnapshot(self: SimulatedCharacterService, player: Player)
	const playerPosition = self:_getPlayerPosition(player)
	const debugCharacters: { SimulatedCharacterTypes.NetworkDebugCharacter } = {}
	if playerPosition then
		for _, character in self._characters do
			if not self:_isCharacterInRange(character, playerPosition) then
				continue
			end

			local targetPosition, targetKey = character:_getTarget()
			const path: { SimulatedCharacterTypes.NetworkDebugPoint } = {}
			if targetPosition and targetKey ~= nil then
				const planarPath = if self._navigation
					then self._navigation:_getDebugPath(character._position, targetKey, targetPosition)
					else { character._position, targetPosition }
				for index, point in planarPath do
					path[index] = {
						x = point.X,
						z = point.Y,
					}
				end
			end

			table.insert(debugCharacters, {
				id = character._id,
				replicationDistance = character._replicationDistance,
				hitboxHeight = character._definition.HitboxHeight,
				stoppingDistance = character:_getStoppingDistance(),
				flockNeighborRadius = character._definition.FlockNeighborRadius,
				hasFlock = character._definition.FlockGroup ~= "",
				hasTarget = targetPosition ~= nil,
				targetX = if targetPosition then targetPosition.X else 0,
				targetZ = if targetPosition then targetPosition.Y else 0,
				path = path,
			})
		end
	end

	const navigation = self._navigation
	SimulatedCharacterNetwork.packets.debugSnapshot.sendTo({
		hasNavigation = navigation ~= nil,
		navigationMinX = if navigation then navigation._min.X else 0,
		navigationMinZ = if navigation then navigation._min.Y else 0,
		navigationMaxX = if navigation then navigation._max.X else 0,
		navigationMaxZ = if navigation then navigation._max.Y else 0,
		characters = debugCharacters,
	}, player)
end

function SimulatedCharacterService._toNetworkDefinition(
	_self: SimulatedCharacterService,
	character: SimulatedCharacter.SimulatedCharacter
): SimulatedCharacterTypes.NetworkDefinition
	const definition = character._definition
	return {
		name = definition.Name,
		templateName = character._templateName,
		scale = definition.Scale,
		placementMode = definition.PlacementMode,
		simulationRate = character._simulationRate or 1,
		cullDistance = definition.CullDistance,
		hitboxRadius = definition.HitboxRadius,
		hitboxHeight = definition.HitboxHeight,
		idleAnimationId = definition.IdleAnimationId,
		walkAnimationId = definition.WalkAnimationId,
		useDefaultAnimations = definition.UseDefaultAnimations,
	}
end

function SimulatedCharacterService._toAnimationCatalog(
	_self: SimulatedCharacterService,
	definition: SimulatedCharacterTypes.ResolvedCharacterDefinition
): SimulatedCharacterTypes.NetworkAnimationCatalog
	const animationIds = table.create(#definition.ActionAnimations)
	for index, actionAnimation in definition.ActionAnimations do
		animationIds[index] = actionAnimation.AnimationId
	end
	return {
		definitionName = definition.Name,
		animationIds = animationIds,
	}
end

function SimulatedCharacterService._getAnimationCatalogs(
	self: SimulatedCharacterService
): { SimulatedCharacterTypes.NetworkAnimationCatalog }
	const definitionNames: { string } = {}
	for definitionName, definition in self._definitions do
		if #definition.ActionAnimations > 0 then
			table.insert(definitionNames, definitionName)
		end
	end
	table.sort(definitionNames)
	const catalogs = table.create(#definitionNames)
	for index, definitionName in definitionNames do
		catalogs[index] = self:_toAnimationCatalog(self._definitions[definitionName])
	end
	return catalogs
end

function SimulatedCharacterService._toNetworkSpawn(
	self: SimulatedCharacterService,
	character: SimulatedCharacter.SimulatedCharacter
): SimulatedCharacterTypes.NetworkSpawn
	return {
		serverTime = self:_getTime(),
		definition = self:_toNetworkDefinition(character),
		state = character:_getNetworkState(),
	}
end

function SimulatedCharacterService._getInitialState(
	self: SimulatedCharacterService,
	player: Player
): { SimulatedCharacterTypes.NetworkSpawn }
	const interest = self:_getPlayerNetworkInterest(player)
	table.clear(interest)
	const playerPosition = self:_getPlayerPosition(player)
	const result = table.create(#self._characters)
	for index, character in self._characters do
		result[index] = self:_toNetworkSpawn(character)
		if playerPosition and self:_isCharacterInRange(character, playerPosition) then
			interest[character._id] = true
			self:_sendCurrentAnimation(character, player)
		end
	end
	return result
end

function SimulatedCharacterService.Destroy(self: SimulatedCharacterService)
	while #self._characters > 0 do
		self:RemoveCharacter(self._characters[#self._characters])
	end
	self._maid:DoCleaning()
end

return SimulatedCharacterService
