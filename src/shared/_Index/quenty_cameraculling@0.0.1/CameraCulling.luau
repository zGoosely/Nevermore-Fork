--!strict
--[=[
	Performs lightweight camera distance culling using spatial cells.

	@class CameraCulling
	@client
]=]

const CollectionService = game:GetService("CollectionService")
const RunService = game:GetService("RunService")
const Workspace = game:GetService("Workspace")

const CameraCullingUtils = require("./CameraCullingUtils")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const PreferredParentUtils = require("@game/ReplicatedStorage/Packages/PreferredParentUtils")
const RxCollectionServiceUtils = require("@game/ReplicatedStorage/Packages/RxCollectionServiceUtils")
const Signal = require("@game/ReplicatedStorage/Packages/Signal")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

const TAG = "CameraCull"
const DISTANCE_ATTRIBUTE = "CameraCullDistance"
const DEFAULT_CULL_DISTANCE = 200
const DEFAULT_CELL_SIZE = 128
const UPDATE_INTERVAL = 0.1
const MIN_CAMERA_MOVEMENT = 0.5

type Entry = {
	Instance: Instance,
	Center: Vector3,
	Radius: number,
	CullDistance: number,
	CellKey: string,
	Culled: boolean,
	OriginalParent: Instance?,
	Changed: Signal.Signal<(boolean)>,
	OriginalEnabled: { [Instance]: boolean },
	OriginalTransparency: { [BasePart]: number },
}

const CameraCulling = {}
CameraCulling.ServiceName = "CameraCulling"
CameraCulling.__index = CameraCulling

export type CameraCulling = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_serviceBag: ServiceBag.ServiceBag,
		_cellSize: number,
		_entries: { [Instance]: Entry },
		_cells: { [string]: { Entry } },
		_visibleEntries: { [Entry]: true },
		_maxCullDistance: number,
		_getCulledInstancesFolder: () -> Instance?,
		_nearbyEntries: { [Entry]: true },
		_updateAccumulator: number,
		_lastCameraPosition: Vector3?,
		_dirty: boolean,
	},
	{} :: typeof({ __index = CameraCulling })
))

local function setEnabled(instance: Instance, enabled: boolean): ()
	if instance:IsA("ParticleEmitter") then
		instance.Enabled = enabled
	elseif instance:IsA("Beam") then
		instance.Enabled = enabled
	elseif instance:IsA("Trail") then
		instance.Enabled = enabled
	elseif instance:IsA("Fire") then
		instance.Enabled = enabled
	elseif instance:IsA("Smoke") then
		instance.Enabled = enabled
	elseif instance:IsA("Sparkles") then
		instance.Enabled = enabled
	elseif instance:IsA("PointLight") then
		instance.Enabled = enabled
	elseif instance:IsA("SpotLight") then
		instance.Enabled = enabled
	elseif instance:IsA("SurfaceLight") then
		instance.Enabled = enabled
	elseif instance:IsA("Highlight") then
		instance.Enabled = enabled
	elseif instance:IsA("BillboardGui") then
		instance.Enabled = enabled
	elseif instance:IsA("SurfaceGui") then
		instance.Enabled = enabled
	end
end

local function isEnabledInstance(instance: Instance): boolean
	return instance:IsA("ParticleEmitter")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
		or instance:IsA("Fire")
		or instance:IsA("Smoke")
		or instance:IsA("Sparkles")
		or instance:IsA("PointLight")
		or instance:IsA("SpotLight")
		or instance:IsA("SurfaceLight")
		or instance:IsA("Highlight")
		or instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
end

local function getEnabled(instance: Instance): boolean
	if instance:IsA("ParticleEmitter") then
		return instance.Enabled
	elseif instance:IsA("Beam") then
		return instance.Enabled
	elseif instance:IsA("Trail") then
		return instance.Enabled
	elseif instance:IsA("Fire") then
		return instance.Enabled
	elseif instance:IsA("Smoke") then
		return instance.Enabled
	elseif instance:IsA("Sparkles") then
		return instance.Enabled
	elseif instance:IsA("PointLight") then
		return instance.Enabled
	elseif instance:IsA("SpotLight") then
		return instance.Enabled
	elseif instance:IsA("SurfaceLight") then
		return instance.Enabled
	elseif instance:IsA("Highlight") then
		return instance.Enabled
	elseif instance:IsA("BillboardGui") then
		return instance.Enabled
	elseif instance:IsA("SurfaceGui") then
		return instance.Enabled
	end
	return false
end

function CameraCulling.Init(self: CameraCulling, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._cellSize = DEFAULT_CELL_SIZE
	self._entries = {}
	self._cells = {}
	self._visibleEntries = {}
	self._maxCullDistance = DEFAULT_CULL_DISTANCE
	self._nearbyEntries = {}
	self._updateAccumulator = UPDATE_INTERVAL
	self._lastCameraPosition = nil
	self._dirty = true
	self._getCulledInstancesFolder =
		PreferredParentUtils.createPreferredParentRetriever(script, "CulledInstances", true)
end

function CameraCulling.Start(self: CameraCulling): ()
	self._maid:Add(RxCollectionServiceUtils.observeTaggedBrio(TAG):Subscribe(function(brio)
		const instance = brio:GetValue()
		self:_register(instance)
		self._maid:Add(brio:GetDiedSignal():Connect(function()
			self:_unregister(instance)
		end))
	end))
	self._maid:Add(RunService.Heartbeat:Connect(function(deltaTime: number)
		self:_step(deltaTime)
	end))
end

--[=[
	Observes whether an instance is currently culled.

	@within CameraCulling
	@param instance Instance
	@return Observable.Observable<boolean>
]=]
function CameraCulling.ObserveShouldCullInstance(self: CameraCulling, instance: Instance)
	assert(t.Instance(instance), "Bad instance")
	const entry = self:_getOrCreateEntry(instance)
	return Observable.new(function(subscription)
		subscription:Fire(entry.Culled)
		return entry.Changed:Connect(function(culled: boolean)
			subscription:Fire(culled)
		end)
	end)
end

--[=[
	Immediately culls an instance and its supported renderable descendants.

	@within CameraCulling
	@param instance Instance
	]=]
function CameraCulling.Cull(self: CameraCulling, instance: Instance): ()
	assert(t.Instance(instance), "Bad instance")
	self:_setCulled(self:_getOrCreateEntry(instance), true)
end

--[=[
	Immediately restores an instance and its supported renderable descendants.

	@within CameraCulling
	@param instance Instance
	]=]
function CameraCulling.Uncull(self: CameraCulling, instance: Instance): ()
	assert(t.Instance(instance), "Bad instance")
	self:_setCulled(self:_getOrCreateEntry(instance), false)
end

--[=[
	Registers an instance for automatic camera-distance culling.

	@within CameraCulling
	@param instance Instance
	]=]
function CameraCulling.AutomaticallyCull(_self: CameraCulling, instance: Instance): ()
	assert(t.Instance(instance), "Bad instance")
	CollectionService:AddTag(instance, TAG)
end

function CameraCulling._getOrCreateEntry(self: CameraCulling, instance: Instance): Entry
	const existing = self._entries[instance]
	if existing then
		return existing
	end

	const center, radius = CameraCullingUtils.getBounds(instance)
	const resolvedCenter = center or Vector3.zero
	const resolvedRadius = radius or 0
	const attributeDistance = instance:GetAttribute(DISTANCE_ATTRIBUTE)
	const cullDistance = if t.numberPositive(attributeDistance) then attributeDistance else DEFAULT_CULL_DISTANCE
	const x, y, z = CameraCullingUtils.getCellCoordinates(resolvedCenter, self._cellSize)
	const entry: Entry = {
		Instance = instance,
		Center = resolvedCenter,
		Radius = resolvedRadius,
		CullDistance = cullDistance,
		CellKey = CameraCullingUtils.getCellKey(x, y, z),
		Culled = false,
		OriginalParent = nil,
		Changed = Signal.new(),
		OriginalEnabled = {},
		OriginalTransparency = {},
	}
	self._entries[instance] = entry
	self._cells[entry.CellKey] = self._cells[entry.CellKey] or {}
	table.insert(self._cells[entry.CellKey], entry)
	self._visibleEntries[entry] = true
	self._maxCullDistance = math.max(self._maxCullDistance, cullDistance)
	self._dirty = true
	return entry
end

function CameraCulling._register(self: CameraCulling, instance: Instance): ()
	self:_getOrCreateEntry(instance)
end

function CameraCulling._unregister(self: CameraCulling, instance: Instance): ()
	const entry = self._entries[instance]
	if not entry then
		return
	end
	self:_setCulled(entry, false)
	self._entries[instance] = nil
	self._visibleEntries[entry] = nil
	self._dirty = true
	entry.Changed:Destroy()
end

function CameraCulling._setCulled(self: CameraCulling, entry: Entry, culled: boolean): ()
	if entry.Culled == culled then
		return
	end

	entry.Culled = culled
	if culled then
		self._visibleEntries[entry] = nil
		self:_hideEntry(entry)
	else
		self._visibleEntries[entry] = true
		self:_showEntry(entry)
	end
	entry.Changed:Fire(culled)
end

function CameraCulling._hideEntry(self: CameraCulling, entry: Entry): ()
	local function hide(instance: Instance): ()
		if instance:IsA("BasePart") then
			entry.OriginalTransparency[instance] = instance.LocalTransparencyModifier
			instance.LocalTransparencyModifier = 1
		elseif isEnabledInstance(instance) then
			entry.OriginalEnabled[instance] = getEnabled(instance)
			setEnabled(instance, false)
		end
	end

	hide(entry.Instance)
	for _, descendant in entry.Instance:GetDescendants() do
		hide(descendant)
	end

	entry.OriginalParent = entry.Instance.Parent
	const culledInstancesFolder = self._getCulledInstancesFolder()
	if culledInstancesFolder then
		entry.Instance.Parent = culledInstancesFolder
	end
end

function CameraCulling._showEntry(_self: CameraCulling, entry: Entry): ()
	if entry.OriginalParent and entry.OriginalParent.Parent then
		entry.Instance.Parent = entry.OriginalParent
	else
		entry.Instance.Parent = nil
	end
	entry.OriginalParent = nil

	for instance, enabled in entry.OriginalEnabled do
		if instance.Parent then
			setEnabled(instance, enabled)
		end
	end
	for instance, transparency in entry.OriginalTransparency do
		if instance.Parent then
			instance.LocalTransparencyModifier = transparency
		end
	end
	table.clear(entry.OriginalEnabled)
	table.clear(entry.OriginalTransparency)
end

function CameraCulling._getNearbyEntries(self: CameraCulling, position: Vector3): { [Entry]: true }
	const x, y, z = CameraCullingUtils.getCellCoordinates(position, self._cellSize)
	const cellRadius = math.ceil(self._maxCullDistance / self._cellSize) + 1
	const result = self._nearbyEntries
	table.clear(result)
	for cellX = x - cellRadius, x + cellRadius do
		for cellY = y - cellRadius, y + cellRadius do
			for cellZ = z - cellRadius, z + cellRadius do
				const cell = self._cells[CameraCullingUtils.getCellKey(cellX, cellY, cellZ)]
				if cell then
					for _, entry in cell do
						result[entry] = true
					end
				end
			end
		end
	end
	return result
end

function CameraCulling._step(self: CameraCulling, deltaTime: number): ()
	self._updateAccumulator += deltaTime
	if self._updateAccumulator < UPDATE_INTERVAL then
		return
	end
	self._updateAccumulator %= UPDATE_INTERVAL

	const camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	const cameraPosition = camera.CFrame.Position
	if
		not self._dirty
		and self._lastCameraPosition
		and (cameraPosition - self._lastCameraPosition).Magnitude < MIN_CAMERA_MOVEMENT
	then
		return
	end
	self._lastCameraPosition = cameraPosition
	self._dirty = false

	const nearbyEntries = self:_getNearbyEntries(cameraPosition)
	for entry in nearbyEntries do
		const shouldCull = CameraCullingUtils.shouldCull(cameraPosition, entry.Center, entry.Radius, entry.CullDistance)
		self:_setCulled(entry, shouldCull)
	end
	for entry in self._visibleEntries do
		if not nearbyEntries[entry] then
			self:_setCulled(entry, true)
		end
	end
end

function CameraCulling.Destroy(self: CameraCulling): ()
	for _, entry in self._entries do
		self:_setCulled(entry, false)
		entry.Changed:Destroy()
	end
	self._maid:DoCleaning()
end

return CameraCulling
