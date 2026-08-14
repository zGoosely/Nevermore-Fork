--!strict
--!optimize 2
--[=[
	Applies frame-budgeted, overlap-safe local visibility mutations.

	@class ClientCullingVisibilityState
	@client
]=]
const ClientCullingTypes = require("./ClientCullingTypes")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const TransparencyService = require("@game/ReplicatedStorage/Packages/TransparencyService")
const t = require("@game/ReplicatedStorage/Packages/t")

type CullMode = ClientCullingTypes.CullMode
type CullOwner = ClientCullingTypes.CullOwner

type PropertyState = {
	Original: boolean,
	Owners: { [CullOwner]: true },
}

type Mutation = {
	Owner: CullOwner,
	Instance: Instance,
	Mode: CullMode,
	Add: boolean,
	Generation: number,
	ExpectedDesiredCulled: boolean,
}

const ENABLED_CLASS_NAMES = table.freeze({
	Beam = true,
	BillboardGui = true,
	Fire = true,
	Highlight = true,
	ParticleEmitter = true,
	PointLight = true,
	Smoke = true,
	Sparkles = true,
	SpotLight = true,
	SurfaceGui = true,
	SurfaceLight = true,
	Trail = true,
})

const ClientCullingVisibilityState = {}
ClientCullingVisibilityState.ClassName = "ClientCullingVisibilityState"
ClientCullingVisibilityState.__index = ClientCullingVisibilityState

export type ClientCullingVisibilityState = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_transparencyService: TransparencyService.TransparencyService,
		_addMutations: { Mutation },
		_addMutationHead: number,
		_removeMutations: { Mutation },
		_removeMutationHead: number,
		_ownerGenerations: { [CullOwner]: number },
		_ownerDesiredCulled: { [CullOwner]: boolean },
		_ownerModes: { [CullOwner]: CullMode },
		_ownerInstances: { [CullOwner]: { [Instance]: true } },
		_enabledStates: { [Instance]: PropertyState },
		_shadowStates: { [BasePart]: PropertyState },
	},
	{} :: typeof({ __index = ClientCullingVisibilityState })
))

function ClientCullingVisibilityState.new(
	transparencyService: TransparencyService.TransparencyService
): ClientCullingVisibilityState
	assert(t.table(transparencyService), "Bad transparencyService")

	const self = setmetatable({}, ClientCullingVisibilityState) :: ClientCullingVisibilityState
	self._maid = Maid.new()
	self._transparencyService = transparencyService
	self._addMutations = {}
	self._addMutationHead = 1
	self._removeMutations = {}
	self._removeMutationHead = 1
	self._ownerGenerations = setmetatable({}, { __mode = "k" }) :: any
	self._ownerDesiredCulled = setmetatable({}, { __mode = "k" }) :: any
	self._ownerModes = setmetatable({}, { __mode = "k" }) :: any
	self._ownerInstances = setmetatable({}, { __mode = "k" }) :: any
	self._enabledStates = setmetatable({}, { __mode = "k" }) :: any
	self._shadowStates = setmetatable({}, { __mode = "k" }) :: any
	return self
end

--[=[
	Queues a root to enter or leave one culling mode.

	@within ClientCullingVisibilityState
	@param owner CullOwner
	@param root Instance
	@param mode CullMode
	@param culled boolean
]=]
function ClientCullingVisibilityState.SetRootCulled(
	self: ClientCullingVisibilityState,
	owner: CullOwner,
	root: Instance,
	mode: CullMode,
	culled: boolean
): ()
	assert(t.table(owner), "Bad owner")
	assert(t.Instance(root), "Bad root")
	assert(t.literal("Render", "Shadows")(mode), "Bad mode")
	assert(t.boolean(culled), "Bad culled")

	if self._ownerDesiredCulled[owner] == culled and self._ownerModes[owner] == mode then
		return
	end

	const generation = (self._ownerGenerations[owner] or 0) + 1
	self._ownerGenerations[owner] = generation
	self._ownerDesiredCulled[owner] = culled
	self._ownerModes[owner] = mode

	if culled then
		self:_queueMutation(owner, root, mode, true, generation, true)
		for _, descendant in root:GetDescendants() do
			self:_queueMutation(owner, descendant, mode, true, generation, true)
		end
		return
	end

	const instances = self._ownerInstances[owner]
	if not instances then
		self._ownerDesiredCulled[owner] = nil
		self._ownerModes[owner] = nil
		return
	end
	for instance in instances do
		self:_queueMutation(owner, instance, mode, false, generation, false)
	end
end

--[=[
	Queues a newly added descendant when its owner is currently culled.

	@within ClientCullingVisibilityState
	@param owner CullOwner
	@param descendant Instance
]=]
function ClientCullingVisibilityState.AddDescendant(
	self: ClientCullingVisibilityState,
	owner: CullOwner,
	descendant: Instance
): ()
	assert(t.table(owner), "Bad owner")
	assert(t.Instance(descendant), "Bad descendant")

	if self._ownerDesiredCulled[owner] ~= true then
		return
	end

	const mode = self._ownerModes[owner]
	const generation = self._ownerGenerations[owner]
	if mode and generation then
		self:_queueMutation(owner, descendant, mode, true, generation, true)
	end
end

--[=[
	Queues restoration for a descendant leaving a currently culled root.

	@within ClientCullingVisibilityState
	@param owner CullOwner
	@param descendant Instance
]=]
function ClientCullingVisibilityState.RemoveDescendant(
	self: ClientCullingVisibilityState,
	owner: CullOwner,
	descendant: Instance
): ()
	assert(t.table(owner), "Bad owner")
	assert(t.Instance(descendant), "Bad descendant")

	if self._ownerDesiredCulled[owner] ~= true then
		return
	end

	const mode = self._ownerModes[owner]
	const generation = self._ownerGenerations[owner]
	if mode and generation then
		self:_queueMutation(owner, descendant, mode, false, generation, true)
	end
end

--[=[
	Queues cleanup for all visibility state owned by one entry.

	@within ClientCullingVisibilityState
	@param owner CullOwner
]=]
function ClientCullingVisibilityState.RemoveOwner(self: ClientCullingVisibilityState, owner: CullOwner): ()
	assert(t.table(owner), "Bad owner")

	const mode = self._ownerModes[owner]
	if mode then
		self:SetRootCulled(owner, owner._adornee :: Instance, mode, false)
	end
end

--[=[
	Processes at most the requested number of pending visual mutations.

	@within ClientCullingVisibilityState
	@param maximumMutations number
]=]
function ClientCullingVisibilityState.Step(self: ClientCullingVisibilityState, maximumMutations: number): ()
	assert(t.numberPositive(maximumMutations), "Bad maximumMutations")

	local processed = 0
	while processed < maximumMutations and self._removeMutationHead <= #self._removeMutations do
		const mutation = self._removeMutations[self._removeMutationHead]
		self._removeMutationHead += 1
		processed += 1
		self:_applyMutation(mutation)
	end

	if self._removeMutationHead > #self._removeMutations then
		table.clear(self._removeMutations)
		self._removeMutationHead = 1
	end

	while processed < maximumMutations and self._addMutationHead <= #self._addMutations do
		const mutation = self._addMutations[self._addMutationHead]
		self._addMutationHead += 1
		processed += 1
		self:_applyMutation(mutation)
	end

	if self._addMutationHead > #self._addMutations then
		table.clear(self._addMutations)
		self._addMutationHead = 1
	end
end

function ClientCullingVisibilityState._queueMutation(
	self: ClientCullingVisibilityState,
	owner: CullOwner,
	instance: Instance,
	mode: CullMode,
	add: boolean,
	generation: number,
	expectedDesiredCulled: boolean
): ()
	const mutations = if add then self._addMutations else self._removeMutations
	table.insert(mutations, {
		Owner = owner,
		Instance = instance,
		Mode = mode,
		Add = add,
		Generation = generation,
		ExpectedDesiredCulled = expectedDesiredCulled,
	})
end

function ClientCullingVisibilityState._applyMutation(self: ClientCullingVisibilityState, mutation: Mutation): ()
	if self._ownerGenerations[mutation.Owner] ~= mutation.Generation then
		return
	end
	if self._ownerDesiredCulled[mutation.Owner] ~= mutation.ExpectedDesiredCulled then
		return
	end

	local ownerInstances = self._ownerInstances[mutation.Owner]
	if mutation.Add then
		const root = mutation.Owner._adornee :: Instance?
		if not root or (mutation.Instance ~= root and not mutation.Instance:IsDescendantOf(root)) then
			return
		end
		if ownerInstances and ownerInstances[mutation.Instance] then
			return
		end
		if not ownerInstances then
			const newOwnerInstances: { [Instance]: true } = setmetatable({}, { __mode = "k" }) :: any
			self._ownerInstances[mutation.Owner] = newOwnerInstances
			ownerInstances = newOwnerInstances
		end
		const resolvedOwnerInstances = ownerInstances :: { [Instance]: true }
		resolvedOwnerInstances[mutation.Instance] = true
		self:_applyOwner(mutation.Owner, mutation.Instance, mutation.Mode)
	elseif ownerInstances and ownerInstances[mutation.Instance] then
		ownerInstances[mutation.Instance] = nil
		self:_releaseOwner(mutation.Owner, mutation.Instance, mutation.Mode)
		if next(ownerInstances) == nil and self._ownerDesiredCulled[mutation.Owner] == false then
			self._ownerInstances[mutation.Owner] = nil
			self._ownerDesiredCulled[mutation.Owner] = nil
			self._ownerModes[mutation.Owner] = nil
		end
	end
end

function ClientCullingVisibilityState._applyOwner(
	self: ClientCullingVisibilityState,
	owner: CullOwner,
	instance: Instance,
	mode: CullMode
): ()
	if mode == "Shadows" then
		if instance:IsA("BasePart") then
			self:_addShadowOwner(owner, instance)
		end
		return
	end

	if instance:IsA("BasePart") then
		self._transparencyService:SetLocalTransparencyModifier(owner, instance, 1)
		self:_addShadowOwner(owner, instance)
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		self._transparencyService:SetTransparency(owner, instance, 1)
	elseif ENABLED_CLASS_NAMES[instance.ClassName] then
		self:_addEnabledOwner(owner, instance)
	end
end

function ClientCullingVisibilityState._releaseOwner(
	self: ClientCullingVisibilityState,
	owner: CullOwner,
	instance: Instance,
	mode: CullMode
): ()
	if mode == "Shadows" then
		if instance:IsA("BasePart") then
			self:_removeShadowOwner(owner, instance)
		end
		return
	end

	if instance:IsA("BasePart") then
		self._transparencyService:ResetLocalTransparencyModifier(owner, instance)
		self:_removeShadowOwner(owner, instance)
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		self._transparencyService:ResetTransparency(owner, instance)
	elseif ENABLED_CLASS_NAMES[instance.ClassName] then
		self:_removeEnabledOwner(owner, instance)
	end
end

function ClientCullingVisibilityState._addEnabledOwner(
	self: ClientCullingVisibilityState,
	owner: CullOwner,
	instance: Instance
): ()
	local state = self._enabledStates[instance]
	if not state then
		state = {
			Original = (instance :: any).Enabled,
			Owners = {},
		}
		self._enabledStates[instance] = state
	end
	state.Owners[owner] = true
	(instance :: any).Enabled = false
end

function ClientCullingVisibilityState._removeEnabledOwner(
	self: ClientCullingVisibilityState,
	owner: CullOwner,
	instance: Instance
): ()
	const state = self._enabledStates[instance]
	if not state then
		return
	end
	state.Owners[owner] = nil
	if next(state.Owners) == nil then
		(instance :: any).Enabled = state.Original
		self._enabledStates[instance] = nil
	end
end

function ClientCullingVisibilityState._addShadowOwner(
	self: ClientCullingVisibilityState,
	owner: CullOwner,
	part: BasePart
): ()
	local state = self._shadowStates[part]
	if not state then
		state = {
			Original = part.CastShadow,
			Owners = {},
		}
		self._shadowStates[part] = state
	end
	state.Owners[owner] = true
	part.CastShadow = false
end

function ClientCullingVisibilityState._removeShadowOwner(
	self: ClientCullingVisibilityState,
	owner: CullOwner,
	part: BasePart
): ()
	const state = self._shadowStates[part]
	if not state then
		return
	end
	state.Owners[owner] = nil
	if next(state.Owners) == nil then
		part.CastShadow = state.Original
		self._shadowStates[part] = nil
	end
end

function ClientCullingVisibilityState.Destroy(self: ClientCullingVisibilityState): ()
	for owner, instances in self._ownerInstances do
		const mode = self._ownerModes[owner]
		if mode then
			for instance in instances do
				self:_releaseOwner(owner, instance, mode)
			end
		end
	end

	self._maid:DoCleaning()
	table.clear(self._addMutations)
	table.clear(self._removeMutations)
	table.clear(self._ownerGenerations)
	table.clear(self._ownerDesiredCulled)
	table.clear(self._ownerModes)
	table.clear(self._ownerInstances)
	table.clear(self._enabledStates)
	table.clear(self._shadowStates)
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return ClientCullingVisibilityState
