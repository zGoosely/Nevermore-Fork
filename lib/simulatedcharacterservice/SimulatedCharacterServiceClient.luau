--!strict
--!optimize 2
--[=[
	Receives simulated character state and renders only characters admitted by
	ClientCulling.

	@class SimulatedCharacterServiceClient
]=]

const RunService = game:GetService("RunService")
const Players = game:GetService("Players")

const require = require("../Loader").load()

const ClientCulling = require("ClientCulling")
const DefaultCharacterAnimationUtils = require("DefaultCharacterAnimationUtils")
const Maid = require("Maid")
const Promise = require("Promise")
const ServiceBag = require("ServiceBag")
const SimulatedCharacterClient = require("SimulatedCharacterClient")
const SimulatedCharacterConstants = require("SimulatedCharacterConstants")
const SimulatedCharacterNetwork = require("SimulatedCharacterNetwork")
const SimulatedCharacterStateCodec = require("SimulatedCharacterStateCodec")
const SimulatedCharacterTemplateProvider = require("SimulatedCharacterTemplateProvider")
const SimulatedCharacterTypes = require("SimulatedCharacterTypes")
const TableUtils = require("TableUtils")
const TimeSyncService = require("TimeSyncService")

const DEBUG_REQUEST_INTERVAL = 0.2

type PendingState = {
	state: SimulatedCharacterTypes.NetworkState,
	serverTime: number,
}

type PendingMotion = {
	motion: SimulatedCharacterTypes.NetworkMotionState,
	serverTime: number,
}

type PendingAnimationControl =
	{
		kind: "play",
		data: SimulatedCharacterTypes.NetworkAnimationPlay,
	}
	| {
		kind: "stop",
		data: SimulatedCharacterTypes.NetworkAnimationStop,
	}

const SimulatedCharacterServiceClient = {}
SimulatedCharacterServiceClient.ServiceName = "SimulatedCharacterServiceClient"

export type SimulatedCharacterServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_timeSyncService: TimeSyncService.TimeSyncService,
		_clock: TimeSyncService.SyncedClock?,
		_templateProvider: any,
		_renderFolder: Folder,
		_charactersById: { [number]: SimulatedCharacterClient.SimulatedCharacterClient },
		_renderCharacters: { SimulatedCharacterClient.SimulatedCharacterClient },
		_pendingStatesById: { [number]: PendingState },
		_pendingMotionsById: { [number]: PendingMotion },
		_pendingSimulationRatesById: { [number]: number },
		_pendingAnimationsById: { [number]: PendingAnimationControl },
		_animationCatalogsByDefinition: { [string]: { string } },
		_removedIds: { [number]: boolean },
		_modelPool: { [string]: { Model } },
		_defaultIdleAnimationId: string,
		_defaultWalkAnimationId: string,
		_debugVisualizer: any?,
		_destroyed: boolean,
	},
	{} :: typeof({ __index = SimulatedCharacterServiceClient })
))

function SimulatedCharacterServiceClient.Init(self: SimulatedCharacterServiceClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._timeSyncService = self._serviceBag:GetService(TimeSyncService)
	self._clock = nil
	self._templateProvider = self._serviceBag:GetService(SimulatedCharacterTemplateProvider)
	self._charactersById = {}
	self._renderCharacters = {}
	self._pendingStatesById = {}
	self._pendingMotionsById = {}
	self._pendingSimulationRatesById = {}
	self._pendingAnimationsById = {}
	self._animationCatalogsByDefinition = {}
	self._removedIds = {}
	self._modelPool = {}
	self._defaultIdleAnimationId = ""
	self._defaultWalkAnimationId = ""
	self._debugVisualizer = nil
	self._destroyed = false

	const renderFolder = Instance.new("Folder")
	renderFolder.Name = "SimulatedCharacters"
	renderFolder.Parent = workspace
	self._renderFolder = self._maid:Add(renderFolder)

	ClientCulling.Start()
	self:_observeDefaultAnimations()
	SimulatedCharacterNetwork.packets.spawned.listen(function(spawn: SimulatedCharacterTypes.NetworkSpawn)
		self:_handleSpawn(spawn)
	end)
	SimulatedCharacterNetwork.packets.removed.listen(function(id: number)
		self:_handleRemove(id)
	end)
	SimulatedCharacterNetwork.packets.simulationRateChanged.listen(
		function(data: SimulatedCharacterTypes.NetworkSimulationRate)
			self:_handleSimulationRate(data.id, data.rate)
		end
	)
	SimulatedCharacterNetwork.packets.animationCatalogChanged.listen(
		function(catalog: SimulatedCharacterTypes.NetworkAnimationCatalog)
			self:_handleAnimationCatalog(catalog)
		end
	)
	SimulatedCharacterNetwork.packets.animationPlayed.listen(
		function(data: SimulatedCharacterTypes.NetworkAnimationPlay)
			self:_handleAnimationPlayed(data)
		end
	)
	SimulatedCharacterNetwork.packets.animationStopped.listen(
		function(data: SimulatedCharacterTypes.NetworkAnimationStop)
			self:_handleAnimationStopped(data)
		end
	)
	SimulatedCharacterNetwork.packets.stateChanged.listen(function(data: {
		serverTime: number,
		state: SimulatedCharacterTypes.NetworkState,
	})
		self:_handleState(data.state, data.serverTime)
	end)
	SimulatedCharacterNetwork.packets.snapshot.listen(function(snapshot: SimulatedCharacterTypes.NetworkSnapshot)
		const motions = SimulatedCharacterStateCodec.decode(snapshot.originX, snapshot.originZ, snapshot.data)
		for _, motion in motions do
			self:_handleMotion(motion, snapshot.serverTime)
		end
	end)
	SimulatedCharacterNetwork.packets.debugSnapshot.listen(
		function(snapshot: SimulatedCharacterTypes.NetworkDebugSnapshot)
			if self._destroyed then
				return
			end
			const debugVisualizer = self._debugVisualizer
			if debugVisualizer then
				debugVisualizer:_applySnapshot(snapshot)
			end
		end
	)
end

function SimulatedCharacterServiceClient.Start(self: SimulatedCharacterServiceClient)
	self._timeSyncService
		:PromiseSyncedClock()
		:Then(function(clock: TimeSyncService.SyncedClock)
			if self._destroyed then
				return
			end

			self._clock = clock
			self._maid:Add(RunService.RenderStepped:Connect(function()
				const renderTime = clock:GetTime() - SimulatedCharacterConstants.DEFAULT_INTERPOLATION_DELAY
				for _, character in self._renderCharacters do
					character:_render(renderTime)
				end
			end))
			self:_requestAnimationCatalogs()
			self:_requestInitialState()
		end)
		:Catch(warn)
end

function SimulatedCharacterServiceClient._requestAnimationCatalogs(self: SimulatedCharacterServiceClient)
	const success, resultOrError = (pcall :: any)(function()
		return SimulatedCharacterNetwork.queries.requestAnimationCatalogs.invoke(nil)
	end)
	if not success then
		warn(`[SimulatedCharacterServiceClient] - Failed to request animation catalogs: {resultOrError}`)
		return
	end
	if type(resultOrError) ~= "table" then
		warn("[SimulatedCharacterServiceClient] - Server returned invalid animation catalogs")
		return
	end

	for _, catalog in resultOrError :: { SimulatedCharacterTypes.NetworkAnimationCatalog } do
		self:_handleAnimationCatalog(catalog)
	end
end

--[=[
	Enables or disables local debug drawing. While enabled, the client requests
	nearby pathfinding data from the server at 5 Hz.

	@within SimulatedCharacterServiceClient
	@param enabled boolean
]=]
function SimulatedCharacterServiceClient.SetDebug(self: SimulatedCharacterServiceClient, enabled: boolean)
	assert(type(enabled) == "boolean", "Bad enabled")
	assert(not self._destroyed, "SimulatedCharacterServiceClient is destroyed")
	if (self._debugVisualizer ~= nil) == enabled then
		return
	end

	self._maid._debugRequestConnection = nil
	self._maid._debugVisualizer = nil
	self._debugVisualizer = nil
	if not enabled then
		return
	end

	const debugVisualizer = require("SimulatedCharacterDebug").new(self)
	self._debugVisualizer = debugVisualizer
	self._maid._debugVisualizer = debugVisualizer
	SimulatedCharacterNetwork.packets.debugRequested.send(true)
	local accumulator = 0
	self._maid._debugRequestConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		accumulator += deltaTime
		if accumulator >= DEBUG_REQUEST_INTERVAL then
			accumulator %= DEBUG_REQUEST_INTERVAL
			SimulatedCharacterNetwork.packets.debugRequested.send(true)
		end
	end)
end

--[=[
	Returns a client character by numeric id.

	@within SimulatedCharacterServiceClient
	@param id number
	@return SimulatedCharacterClient?
]=]
function SimulatedCharacterServiceClient.GetCharacter(
	self: SimulatedCharacterServiceClient,
	id: number
): SimulatedCharacterClient.SimulatedCharacterClient?
	return self._charactersById[id]
end

--[=[
	Returns every currently known client character.

	@within SimulatedCharacterServiceClient
	@return { SimulatedCharacterClient }
]=]
function SimulatedCharacterServiceClient.GetCharacters(
	self: SimulatedCharacterServiceClient
): { SimulatedCharacterClient.SimulatedCharacterClient }
	const result = table.create(30)
	for _, character in self._charactersById do
		table.insert(result, character)
	end
	return result
end

function SimulatedCharacterServiceClient._requestInitialState(self: SimulatedCharacterServiceClient)
	const success, resultOrError = (pcall :: any)(function()
		return SimulatedCharacterNetwork.queries.requestInitialState.invoke(nil)
	end)
	if not success then
		warn(`[SimulatedCharacterServiceClient] - Failed to request initial state: {resultOrError}`)
		return
	end
	if type(resultOrError) ~= "table" then
		warn("[SimulatedCharacterServiceClient] - Server returned an invalid initial state")
		return
	end

	for _, spawn in resultOrError :: { SimulatedCharacterTypes.NetworkSpawn } do
		self:_handleSpawn(spawn)
	end
end

function SimulatedCharacterServiceClient._observeDefaultAnimations(self: SimulatedCharacterServiceClient)
	const localPlayer = Players.LocalPlayer
	local function handleCharacter(character: Model)
		self._maid
			:GivePromise(DefaultCharacterAnimationUtils.promiseAnimationIdsAsync(character))
			:Then(function(animationIds: DefaultCharacterAnimationUtils.AnimationIds)
				if self._destroyed or localPlayer.Character ~= character then
					return
				end

				self._defaultIdleAnimationId = animationIds.idleAnimationId
				self._defaultWalkAnimationId = animationIds.walkAnimationId
				for _, simulatedCharacter in self._renderCharacters do
					simulatedCharacter:_refreshAnimations()
				end
			end)
			:Catch(warn)
	end

	self._maid:Add(localPlayer.CharacterAdded:Connect(handleCharacter))
	if localPlayer.Character then
		task.spawn(handleCharacter, localPlayer.Character)
	end
end

function SimulatedCharacterServiceClient._handleSpawn(
	self: SimulatedCharacterServiceClient,
	spawn: SimulatedCharacterTypes.NetworkSpawn
)
	if self._destroyed or self._removedIds[spawn.state.id] then
		return
	end

	const existing = self._charactersById[spawn.state.id]
	if existing then
		existing:_setSimulationRate(spawn.definition.simulationRate)
		existing:_pushState(spawn.state, spawn.serverTime)
		return
	end

	const character = SimulatedCharacterClient.new(self, spawn)
	self._charactersById[spawn.state.id] = character
	const pendingSimulationRate = self._pendingSimulationRatesById[spawn.state.id]
	if pendingSimulationRate ~= nil then
		self._pendingSimulationRatesById[spawn.state.id] = nil
		character:_setSimulationRate(pendingSimulationRate)
	end
	const pendingState = self._pendingStatesById[spawn.state.id]
	if pendingState then
		self._pendingStatesById[spawn.state.id] = nil
		character:_pushState(pendingState.state, pendingState.serverTime, true)
	end
	const pendingMotion = self._pendingMotionsById[spawn.state.id]
	if pendingMotion then
		self._pendingMotionsById[spawn.state.id] = nil
		character:_pushMotion(pendingMotion.motion, pendingMotion.serverTime)
	end
	const pendingAnimation = self._pendingAnimationsById[spawn.state.id]
	if pendingAnimation then
		self._pendingAnimationsById[spawn.state.id] = nil
		if pendingAnimation.kind == "play" then
			character:_playActionAnimation(pendingAnimation.data)
		else
			character:_stopActionAnimation(pendingAnimation.data)
		end
	end
end

function SimulatedCharacterServiceClient._handleAnimationCatalog(
	self: SimulatedCharacterServiceClient,
	catalog: SimulatedCharacterTypes.NetworkAnimationCatalog
)
	if self._destroyed then
		return
	end

	const animationIds = table.clone(catalog.animationIds)
	self._animationCatalogsByDefinition[catalog.definitionName] = table.freeze(animationIds)
	for _, character in self._charactersById do
		if character._definition.name == catalog.definitionName then
			character:_refreshActionAnimation()
		end
	end
end

function SimulatedCharacterServiceClient._handleAnimationPlayed(
	self: SimulatedCharacterServiceClient,
	data: SimulatedCharacterTypes.NetworkAnimationPlay
)
	if self._destroyed or self._removedIds[data.id] then
		return
	end

	const character = self._charactersById[data.id]
	if character then
		character:_playActionAnimation(data)
		return
	end

	const pending = self._pendingAnimationsById[data.id]
	if not pending or data.sequence > pending.data.sequence then
		self._pendingAnimationsById[data.id] = {
			kind = "play",
			data = table.clone(data),
		}
	end
end

function SimulatedCharacterServiceClient._handleAnimationStopped(
	self: SimulatedCharacterServiceClient,
	data: SimulatedCharacterTypes.NetworkAnimationStop
)
	if self._destroyed or self._removedIds[data.id] then
		return
	end

	const character = self._charactersById[data.id]
	if character then
		character:_stopActionAnimation(data)
		return
	end

	const pending = self._pendingAnimationsById[data.id]
	if not pending or data.sequence > pending.data.sequence then
		self._pendingAnimationsById[data.id] = {
			kind = "stop",
			data = table.clone(data),
		}
	end
end

function SimulatedCharacterServiceClient._handleState(
	self: SimulatedCharacterServiceClient,
	state: SimulatedCharacterTypes.NetworkState,
	serverTime: number
)
	if self._destroyed or self._removedIds[state.id] then
		return
	end

	const character = self._charactersById[state.id]
	if character then
		character:_pushState(state, serverTime, true)
	else
		const existing = self._pendingStatesById[state.id]
		if not existing or serverTime >= existing.serverTime then
			self._pendingStatesById[state.id] = {
				state = table.clone(state),
				serverTime = serverTime,
			}
		end
	end
end

function SimulatedCharacterServiceClient._handleMotion(
	self: SimulatedCharacterServiceClient,
	motion: SimulatedCharacterTypes.NetworkMotionState,
	serverTime: number
)
	if self._destroyed or self._removedIds[motion.id] then
		return
	end

	const character = self._charactersById[motion.id]
	if character then
		character:_pushMotion(motion, serverTime)
	else
		const existing = self._pendingMotionsById[motion.id]
		if not existing or serverTime >= existing.serverTime then
			self._pendingMotionsById[motion.id] = {
				motion = table.clone(motion),
				serverTime = serverTime,
			}
		end
	end
end

function SimulatedCharacterServiceClient._handleSimulationRate(
	self: SimulatedCharacterServiceClient,
	id: number,
	rate: number
)
	if self._destroyed or self._removedIds[id] then
		return
	end

	const character = self._charactersById[id]
	if character then
		character:_setSimulationRate(rate)
	else
		self._pendingSimulationRatesById[id] = rate
	end
end

function SimulatedCharacterServiceClient._handleRemove(self: SimulatedCharacterServiceClient, id: number)
	if self._destroyed then
		return
	end

	self._removedIds[id] = true
	self._pendingStatesById[id] = nil
	self._pendingMotionsById[id] = nil
	self._pendingSimulationRatesById[id] = nil
	self._pendingAnimationsById[id] = nil
	const character = self._charactersById[id]
	if character then
		self._charactersById[id] = nil
		character:Destroy()
	end
end

function SimulatedCharacterServiceClient._setCharacterRendered(
	self: SimulatedCharacterServiceClient,
	character: SimulatedCharacterClient.SimulatedCharacterClient,
	rendered: boolean
)
	if rendered then
		if character._renderIndex ~= 0 then
			return
		end
		character._renderIndex = #self._renderCharacters + 1
		table.insert(self._renderCharacters, character)
		return
	end

	const index = character._renderIndex
	if index == 0 then
		return
	end

	const lastCharacter = self._renderCharacters[#self._renderCharacters]
	TableUtils.swapRemove(self._renderCharacters, index)
	character._renderIndex = 0
	if lastCharacter and lastCharacter ~= character then
		lastCharacter._renderIndex = index
	end
end

function SimulatedCharacterServiceClient._acquireModelAsync(
	self: SimulatedCharacterServiceClient,
	templateName: string
): Promise.Promise<Model>
	const pool = self._modelPool[templateName]
	if pool then
		while #pool > 0 do
			const model = pool[#pool]
			pool[#pool] = nil
			if typeof(model) == "Instance" and model:IsA("Model") then
				return Promise.resolved(model)
			end
		end
	end

	return self._templateProvider:PromiseCloneTemplate(templateName):Then(function(template: Instance): Model
		assert(template:IsA("Model"), `Template {templateName} must be a Model`)
		return template
	end)
end

function SimulatedCharacterServiceClient._releaseModel(
	self: SimulatedCharacterServiceClient,
	templateName: string,
	model: Model
)
	if self._destroyed then
		model:Destroy()
		return
	end

	model.Parent = nil
	model.Name = templateName
	local pool = self._modelPool[templateName]
	if not pool then
		pool = {}
		self._modelPool[templateName] = pool
	end
	table.insert(pool, model)
end

function SimulatedCharacterServiceClient._getRenderParent(self: SimulatedCharacterServiceClient): Folder
	return self._renderFolder
end

function SimulatedCharacterServiceClient._getTime(self: SimulatedCharacterServiceClient): number
	const clock = self._clock
	return if clock then clock:GetTime() else tick()
end

function SimulatedCharacterServiceClient._getDefaultAnimationId(
	self: SimulatedCharacterServiceClient,
	animationName: "Idle" | "Walk"
): string
	return if animationName == "Idle" then self._defaultIdleAnimationId else self._defaultWalkAnimationId
end

function SimulatedCharacterServiceClient._getActionAnimationId(
	self: SimulatedCharacterServiceClient,
	definitionName: string,
	animationIndex: number
): string?
	const catalog = self._animationCatalogsByDefinition[definitionName]
	return if catalog then catalog[animationIndex] else nil
end

function SimulatedCharacterServiceClient.Destroy(self: SimulatedCharacterServiceClient)
	if self._destroyed then
		return
	end

	self._destroyed = true
	self._debugVisualizer = nil
	for _, character in self._charactersById do
		character:Destroy()
	end
	table.clear(self._charactersById)
	table.clear(self._renderCharacters)
	table.clear(self._pendingStatesById)
	table.clear(self._pendingMotionsById)
	table.clear(self._pendingSimulationRatesById)
	table.clear(self._pendingAnimationsById)
	table.clear(self._animationCatalogsByDefinition)
	for _, pool in self._modelPool do
		for _, model in pool do
			model:Destroy()
		end
	end
	table.clear(self._modelPool)
	self._maid:DoCleaning()
end

return SimulatedCharacterServiceClient
