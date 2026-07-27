--!strict
--!optimize 2
--[=[
	Coordinates indexed distance checks, dynamic refreshes, and visual work.

	@class ClientCullingRegistry
	@client
]=]

const RunService = game:GetService("RunService")
const Workspace = game:GetService("Workspace")

const require = require("../Loader").load()

const ClientCullingConstants = require("ClientCullingConstants")
const ClientCullingSpatialIndex = require("ClientCullingSpatialIndex")
const ClientCullingTypes = require("ClientCullingTypes")
const ClientCullingUtils = require("ClientCullingUtils")
const ClientCullingVisibilityState = require("ClientCullingVisibilityState")
const Maid = require("Maid")
const TransparencyService = require("TransparencyService")
const t = require("t")

type CullEntry = ClientCullingTypes.CullEntry

const ClientCullingRegistry = {}
ClientCullingRegistry.ClassName = "ClientCullingRegistry"
ClientCullingRegistry.__index = ClientCullingRegistry

export type ClientCullingRegistry = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_spatialIndex: ClientCullingSpatialIndex.ClientCullingSpatialIndex,
		_visibilityState: ClientCullingVisibilityState.ClientCullingVisibilityState,
		_entries: { [CullEntry]: true },
		_visibleEntries: { [CullEntry]: true },
		_dynamicEntries: { CullEntry },
		_dynamicIndices: { [CullEntry]: number },
		_dynamicCursor: number,
		_queryGeneration: number,
		_updateAccumulator: number,
		_running: boolean,
		_destroyed: boolean,
	},
	{} :: typeof({ __index = ClientCullingRegistry })
))

function ClientCullingRegistry.new(transparencyService: TransparencyService.TransparencyService): ClientCullingRegistry
	assert(t.table(transparencyService), "Bad transparencyService")

	const self = setmetatable({}, ClientCullingRegistry) :: ClientCullingRegistry
	self._maid = Maid.new()
	self._spatialIndex = ClientCullingSpatialIndex.new()
	self._visibilityState = ClientCullingVisibilityState.new(transparencyService)
	self._entries = {}
	self._visibleEntries = {}
	self._dynamicEntries = {}
	self._dynamicIndices = {}
	self._dynamicCursor = 1
	self._queryGeneration = 0
	self._updateAccumulator = 0
	self._running = false
	self._destroyed = false
	return self
end

function ClientCullingRegistry.Start(self: ClientCullingRegistry): ()
	assert(not self._running, "Already started")
	self._running = true
	self._maid:Add(RunService.Heartbeat:Connect(function(deltaTime)
		debug.profilebegin("ClientCulling.VisualMutations")
		self._visibilityState:Step(ClientCullingConstants.MAX_VISUAL_MUTATIONS_PER_FRAME)
		debug.profileend()

		self._updateAccumulator += deltaTime
		const updateInterval = 1 / ClientCullingConstants.DEFAULT_UPDATE_FREQUENCY
		if self._updateAccumulator < updateInterval then
			return
		end
		self._updateAccumulator %= updateInterval

		debug.profilebegin("ClientCulling.Update")
		self:_refreshDynamicEntries()
		self:_updateCulling()
		debug.profileend()
	end))
	self:_updateCulling()
end

--[=[
	Registers a configured entry with the scheduler.

	@within ClientCullingRegistry
	@param entry CullEntry
]=]
function ClientCullingRegistry.AddEntry(self: ClientCullingRegistry, entry: CullEntry): ()
	assert(t.table(entry), "Bad entry")
	if self._destroyed then
		return
	end
	if self._entries[entry] then
		return
	end

	self._entries[entry] = true
	self._visibleEntries[entry] = true
	self._spatialIndex:AddOrUpdate(entry)
	self:_syncDynamicEntry(entry)
	self:_evaluateEntry(entry, Workspace.CurrentCamera)
end

--[=[
	Updates an entry after its configuration or cached bounds change.

	@within ClientCullingRegistry
	@param entry CullEntry
]=]
function ClientCullingRegistry.UpdateEntry(self: ClientCullingRegistry, entry: CullEntry): ()
	assert(t.table(entry), "Bad entry")
	if self._destroyed then
		return
	end
	if not self._entries[entry] then
		self:AddEntry(entry)
		return
	end

	self._spatialIndex:AddOrUpdate(entry)
	self:_syncDynamicEntry(entry)
	self:_evaluateEntry(entry, Workspace.CurrentCamera)
end

--[=[
	Removes an entry and queues restoration of its owned visual state.

	@within ClientCullingRegistry
	@param entry CullEntry
]=]
function ClientCullingRegistry.RemoveEntry(self: ClientCullingRegistry, entry: CullEntry): ()
	assert(t.table(entry), "Bad entry")
	if self._destroyed then
		return
	end
	if not self._entries[entry] then
		return
	end

	self._entries[entry] = nil
	self._visibleEntries[entry] = nil
	self._spatialIndex:Remove(entry)
	self:_removeDynamicEntry(entry)
	entry:SetCulled(false)
	self._visibilityState:RemoveOwner(entry)
end

--[=[
	Queues a descendant added beneath a currently culled entry.

	@within ClientCullingRegistry
	@param entry CullEntry
	@param descendant Instance
]=]
function ClientCullingRegistry.AddDescendant(self: ClientCullingRegistry, entry: CullEntry, descendant: Instance): ()
	assert(t.table(entry), "Bad entry")
	assert(t.Instance(descendant), "Bad descendant")
	if self._destroyed then
		return
	end
	self._visibilityState:AddDescendant(entry, descendant)
end

--[=[
	Queues restoration for a descendant leaving a culled entry.

	@within ClientCullingRegistry
	@param entry CullEntry
	@param descendant Instance
]=]
function ClientCullingRegistry.RemoveDescendant(self: ClientCullingRegistry, entry: CullEntry, descendant: Instance): ()
	assert(t.table(entry), "Bad entry")
	assert(t.Instance(descendant), "Bad descendant")
	if self._destroyed then
		return
	end
	self._visibilityState:RemoveDescendant(entry, descendant)
end

--[=[
	Queues the render state associated with an entry's target culling state.

	@within ClientCullingRegistry
	@param entry CullEntry
	@param culled boolean
]=]
function ClientCullingRegistry.SetEntryCulled(self: ClientCullingRegistry, entry: CullEntry, culled: boolean): ()
	assert(t.table(entry), "Bad entry")
	assert(t.boolean(culled), "Bad culled")
	if self._destroyed then
		return
	end
	self._visibilityState:SetRootCulled(entry, entry._adornee, entry._mode, culled)
end

function ClientCullingRegistry._evaluateEntry(self: ClientCullingRegistry, entry: CullEntry, camera: Camera?): ()
	if not camera then
		self:_setEntryCulled(entry, false)
		return
	end

	const distance = if entry._culled then entry._config.UncullDistance else entry._config.CullDistance
	self:_setEntryCulled(entry, ClientCullingUtils.shouldCull(entry._bounds, camera.CFrame.Position, distance))
end

function ClientCullingRegistry._setEntryCulled(self: ClientCullingRegistry, entry: CullEntry, culled: boolean): ()
	if entry._culled == culled then
		return
	end

	entry:SetCulled(culled)
	if culled then
		self._visibleEntries[entry] = nil
	else
		self._visibleEntries[entry] = true
	end
end

function ClientCullingRegistry._refreshDynamicEntries(self: ClientCullingRegistry): ()
	const entryCount = #self._dynamicEntries
	if entryCount == 0 then
		self._dynamicCursor = 1
		return
	end

	debug.profilebegin("ClientCulling.DynamicRefresh")
	const refreshCount = math.min(entryCount, ClientCullingConstants.MAX_DYNAMIC_REFRESHES_PER_UPDATE)
	for _ = 1, refreshCount do
		if self._dynamicCursor > #self._dynamicEntries then
			self._dynamicCursor = 1
		end

		const entry = self._dynamicEntries[self._dynamicCursor]
		self._dynamicCursor += 1
		if entry:RefreshDynamicBounds() then
			self._spatialIndex:AddOrUpdate(entry)
		end
	end
	debug.profileend()
end

function ClientCullingRegistry._updateCulling(self: ClientCullingRegistry): ()
	const camera = Workspace.CurrentCamera
	if not camera then
		for entry in self._entries do
			self:_setEntryCulled(entry, false)
		end
		return
	end

	debug.profilebegin("ClientCulling.SpatialQuery")
	self._queryGeneration += 1
	const generation = self._queryGeneration
	const cameraPosition = camera.CFrame.Position
	const candidates = self._spatialIndex:QueryNearby(cameraPosition)
	for _, entry in candidates do
		entry._queryGeneration = generation
		const distance = if entry._culled then entry._config.UncullDistance else entry._config.CullDistance
		self:_setEntryCulled(entry, ClientCullingUtils.shouldCull(entry._bounds, cameraPosition, distance))
	end

	for entry in self._visibleEntries do
		if entry._queryGeneration ~= generation then
			self:_setEntryCulled(entry, true)
		end
	end
	debug.profileend()
end

function ClientCullingRegistry._syncDynamicEntry(self: ClientCullingRegistry, entry: CullEntry): ()
	const index = self._dynamicIndices[entry]
	if entry._config.Dynamic then
		if not index then
			self._dynamicIndices[entry] = #self._dynamicEntries + 1
			table.insert(self._dynamicEntries, entry)
		end
	elseif index then
		self:_removeDynamicEntry(entry)
	end
end

function ClientCullingRegistry._removeDynamicEntry(self: ClientCullingRegistry, entry: CullEntry): ()
	const index = self._dynamicIndices[entry]
	if not index then
		return
	end

	const lastEntry = self._dynamicEntries[#self._dynamicEntries]
	self._dynamicEntries[index] = lastEntry
	self._dynamicEntries[#self._dynamicEntries] = nil
	self._dynamicIndices[entry] = nil
	if lastEntry ~= entry then
		self._dynamicIndices[lastEntry] = index
	end

	if self._dynamicCursor > #self._dynamicEntries + 1 then
		self._dynamicCursor = 1
	end
end

function ClientCullingRegistry.Destroy(self: ClientCullingRegistry): ()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._running = false
	self._maid:DoCleaning()

	for entry in self._entries do
		entry:SetCulled(false)
	end
	self._visibilityState:Destroy()
	self._spatialIndex:Destroy()

	table.clear(self._entries)
	table.clear(self._visibleEntries)
	table.clear(self._dynamicEntries)
	table.clear(self._dynamicIndices)
end

return ClientCullingRegistry
