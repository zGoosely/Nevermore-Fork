--!strict
--[=[
	Provides named Roblox instances as cloneable templates.

	Templates may be declared through containers, lists, or observables. The last
	registered template with a given name is canonical, which makes overrides
	straightforward.

	When initialized on the server, source templates are moved beneath a Camera so
	they do not replicate immediately. Lightweight tombstones advertise their names
	to clients. A client requesting one uses ByteNet to ask the server for a
	temporary, player-scoped copy and caches its own clone locally.

	```lua
	local VehicleTemplates = TemplateProvider.new("VehicleTemplates", script)

	-- Server and client
	local templates = serviceBag:GetService(VehicleTemplates)

	-- Client requests the asset only when needed
	templates:PromiseCloneTemplate("CopCar"):Then(function(copCar)
		copCar.Parent = workspace
	end)
	```

	@class TemplateProvider
]=]

const HttpService = game:GetService("HttpService")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const require = require("../Loader").load()

const Brio = require("Brio")
const DuckTypeUtils = require("DuckTypeUtils")
const Maid = require("Maid")
const Observable = require("Observable")
const Promise = require("Promise")
const ServiceBag = require("ServiceBag")
const Signal = require("Signal")
const StringUtils = require("StringUtils")
const TemplateReplicationModes = require("TemplateReplicationModes")
const TemplateReplicationModesUtils = require("TemplateReplicationModesUtils")

const TemplateProviderNetwork: any = if RunService:IsRunning() then require("TemplateProviderNetwork") else nil

const TOMBSTONE_ID_ATTRIBUTE = "UnreplicatedTemplateId"
const TOMBSTONE_NAME_POSTFIX_UNLOADED = "_Unloaded"
const TOMBSTONE_NAME_POSTFIX_LOADED = "_Loaded"
const PREVENT_REPLICATION_NAME = "PreventReplication"
const REPLICATION_CONTAINER_NAME = "TemplateProviderReplication"
const MISSING_TEMPLATE_WARNING_DELAY = 5
const TEMPLATE_TRANSFER_TIMEOUT = 5
const TEMPORARY_TEMPLATE_LIFETIME = 10

type TemplateEntry = {
	instance: Instance,
	name: string?,
}

type ContainerState = {
	count: number,
	maid: Maid.Maid,
}

type TemplateRequest = {
	providerName: string,
	templateId: string,
}

type TemplateResponse = {
	success: boolean,
	transferId: string?,
	errorMessage: string?,
}

--[=[
	@type TemplateDeclaration Instance | Observable<Brio<Instance>> | table
	@within TemplateProvider
]=]
export type TemplateDeclaration = Instance | Observable.Observable<Brio.Brio<Instance>> | { TemplateDeclaration }

const TemplateProvider = {}
TemplateProvider.ClassName = "TemplateProvider"
TemplateProvider.ServiceName = "TemplateProvider"
TemplateProvider.__index = TemplateProvider

export type TemplateProvider = typeof(setmetatable(
	{} :: {
		ServiceName: string,
		_serviceBag: ServiceBag.ServiceBag,
		_initialTemplates: TemplateDeclaration?,
		_maid: Maid.Maid,
		_replicationMode: TemplateReplicationModes.TemplateReplicationMode,

		_templateEntries: { [string]: { TemplateEntry } },
		_unreplicatedTemplateEntries: { [string]: { TemplateEntry } },
		_containerStates: { [Instance]: ContainerState },
		_tombstoneLookup: { [string]: Instance },

		_pendingTemplatePromises: { [string]: Promise.Promise<Instance> },
		_pendingTombstoneRequests: { [string]: Promise.Promise<Instance> },

		_templateChanged: Signal.Signal<(string, Instance?)>,
		_templateNameAdded: Signal.Signal<string>,
		_templateNameRemoved: Signal.Signal<string>,
		_unreplicatedTemplateChanged: Signal.Signal<(string, Instance?)>,
		_unreplicatedTemplateNameAdded: Signal.Signal<string>,
		_unreplicatedTemplateNameRemoved: Signal.Signal<string>,
	},
	TemplateProvider
))

const SERVER_PROVIDERS: { [string]: TemplateProvider } = {}

--[=[
	Constructs a template provider service definition.

	@within TemplateProvider
	@param providerName string
	@param initialTemplates TemplateDeclaration?
	@return TemplateProvider
]=]
function TemplateProvider.new(providerName: string, initialTemplates: TemplateDeclaration?): TemplateProvider
	assert(type(providerName) == "string" and providerName ~= "", "Bad providerName")

	const self: TemplateProvider = setmetatable({} :: any, TemplateProvider)
	self.ServiceName = providerName
	self._initialTemplates = initialTemplates

	if initialTemplates ~= nil and not self:_isValidTemplateDeclaration(initialTemplates) then
		error(`[TemplateProvider.{providerName}] - Bad initialTemplates of type {typeof(initialTemplates)}`)
	end

	return self
end

--[=[
	Returns whether a value implements TemplateProvider.

	@within TemplateProvider
	@param value any
	@return boolean
]=]
function TemplateProvider.isTemplateProvider(value: any): boolean
	return DuckTypeUtils.isImplementation(TemplateProvider, value)
end

function TemplateProvider.Init(self: TemplateProvider, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._replicationMode = TemplateReplicationModesUtils.inferReplicationMode()

	self._templateEntries = {}
	self._unreplicatedTemplateEntries = {}
	self._containerStates = {}
	self._tombstoneLookup = {}
	self._pendingTemplatePromises = {}
	self._pendingTombstoneRequests = {}

	self._templateChanged = self._maid:Add(Signal.new())
	self._templateNameAdded = self._maid:Add(Signal.new())
	self._templateNameRemoved = self._maid:Add(Signal.new())
	self._unreplicatedTemplateChanged = self._maid:Add(Signal.new())
	self._unreplicatedTemplateNameAdded = self._maid:Add(Signal.new())
	self._unreplicatedTemplateNameRemoved = self._maid:Add(Signal.new())

	if self._replicationMode == TemplateReplicationModes.SERVER then
		self:_registerServerProvider()
	end

	if self._initialTemplates ~= nil then
		self:AddTemplates(self._initialTemplates)
	end
end

--[=[
	Observes the canonical template for a name. It emits `nil` when no loaded
	template is currently available.

	@within TemplateProvider
	@param templateName string
	@return Observable<Instance?>
]=]
function TemplateProvider.ObserveTemplate(
	self: TemplateProvider,
	templateName: string
): Observable.Observable<Instance?>
	assert(type(templateName) == "string", "Bad templateName")
	assert(self._maid, "Not initialized")

	return self:_observeEntry(self._templateEntries, self._templateChanged, templateName)
end

--[=[
	Observes the names of currently loaded templates as brios.

	@within TemplateProvider
	@return Observable<Brio<string>>
]=]
function TemplateProvider.ObserveTemplateNamesBrio(self: TemplateProvider): Observable.Observable<Brio.Brio<string>>
	assert(self._maid, "Not initialized")

	return self:_observeNamesBrio(self._templateEntries, self._templateNameAdded, self._templateNameRemoved)
end

--[=[
	Observes template names advertised by the server but not yet loaded locally.

	@within TemplateProvider
	@return Observable<Brio<string>>
]=]
function TemplateProvider.ObserveUnreplicatedTemplateNamesBrio(
	self: TemplateProvider
): Observable.Observable<Brio.Brio<string>>
	assert(self._maid, "Not initialized")

	return self:_observeNamesBrio(
		self._unreplicatedTemplateEntries,
		self._unreplicatedTemplateNameAdded,
		self._unreplicatedTemplateNameRemoved
	)
end

--[=[
	Returns the currently loaded canonical template.

	@within TemplateProvider
	@param templateName string
	@return Instance?
]=]
function TemplateProvider.GetTemplate(self: TemplateProvider, templateName: string): Instance?
	assert(type(templateName) == "string", "Bad templateName")
	assert(self._maid, "Not initialized")

	return self:_getCanonicalTemplate(self._templateEntries, templateName)
end

--[=[
	Returns a promise for a clone of the requested template.

	On the client this requests an advertised but unloaded template from the
	server through ByteNet and caches the returned source template locally.

	@within TemplateProvider
	@param templateName string
	@return Promise<Instance>
]=]
function TemplateProvider.PromiseCloneTemplate(self: TemplateProvider, templateName: string): Promise.Promise<Instance>
	assert(type(templateName) == "string", "Bad templateName")

	return self:PromiseTemplate(templateName):Then(function(template: Instance): Instance
		return self:_cloneTemplate(template)
	end)
end

--[=[
	Returns a promise for the raw canonical template.

	@within TemplateProvider
	@param templateName string
	@return Promise<Instance>
]=]
function TemplateProvider.PromiseTemplate(self: TemplateProvider, templateName: string): Promise.Promise<Instance>
	assert(type(templateName) == "string", "Bad templateName")
	assert(self._maid, "Not initialized")

	const foundTemplate = self:_getCanonicalTemplate(self._templateEntries, templateName)
	if foundTemplate then
		return Promise.resolved(foundTemplate)
	end

	const pendingPromise = self._pendingTemplatePromises[templateName]
	if pendingPromise then
		return pendingPromise
	end

	const promiseTemplate: Promise.Promise<Instance> = Promise.new()
	const promiseMaid = Maid.new()
	self._pendingTemplatePromises[templateName] = promiseTemplate
	self._maid[promiseTemplate] = promiseMaid

	promiseMaid:Add(self:ObserveTemplate(templateName):Subscribe(function(template: Instance?)
		if template then
			promiseTemplate:Resolve(template)
		end
	end))

	if self._replicationMode == TemplateReplicationModes.CLIENT then
		promiseMaid:Add(self:_observeUnreplicatedTemplate(templateName):Subscribe(function(tombstone: Instance?)
			if not tombstone then
				promiseMaid._request = nil
				return
			end

			const originalName = tombstone.Name
			promiseMaid._request = self:_promiseReplicateTemplateFromTombstone(tombstone)
				:Then(function(template: Instance)
					if tombstone.Parent == nil then
						promiseTemplate:Reject(`Template tombstone for {templateName} was removed`)
						return
					end

					tombstone.Name = StringUtils.removePostfix(originalName, TOMBSTONE_NAME_POSTFIX_UNLOADED)
						.. TOMBSTONE_NAME_POSTFIX_LOADED
					template.Parent = tombstone
					promiseTemplate:Resolve(template)
				end, function(...)
					promiseTemplate:Reject(...)
				end)
		end))
	end

	promiseMaid:Add(task.delay(MISSING_TEMPLATE_WARNING_DELAY, function()
		if self._replicationMode == TemplateReplicationModes.CLIENT then
			if self:_getCanonicalTemplate(self._unreplicatedTemplateEntries, templateName) then
				warn(
					`[TemplateProvider.{self.ServiceName}.PromiseTemplate] - Failed to replicate template {templateName}`
				)
			else
				warn(`[TemplateProvider.{self.ServiceName}.PromiseTemplate] - Template {templateName} is not known`)
			end
		else
			warn(`[TemplateProvider.{self.ServiceName}.PromiseTemplate] - Missing template {templateName}`)
		end
	end))

	promiseMaid:Add(function()
		if promiseTemplate:IsPending() then
			promiseTemplate:Reject(`TemplateProvider {self.ServiceName} was destroyed`)
		end
	end)

	promiseTemplate:Finally(function()
		self._pendingTemplatePromises[templateName] = nil
		self._maid[promiseTemplate] = nil
	end)

	return promiseTemplate
end

--[=[
	Clones a loaded template immediately.

	Use [TemplateProvider.PromiseCloneTemplate] on the client when a template is
	advertised but has not yet been loaded.

	@within TemplateProvider
	@param templateName string
	@return Instance
]=]
function TemplateProvider.CloneTemplate(self: TemplateProvider, templateName: string): Instance
	assert(type(templateName) == "string", "Bad templateName")
	assert(self._maid, "Not initialized")

	const template = self:_getCanonicalTemplate(self._templateEntries, templateName)
	if template then
		return self:_cloneTemplate(template)
	end

	if self:_getCanonicalTemplate(self._unreplicatedTemplateEntries, templateName) then
		error(
			`[TemplateProvider.{self.ServiceName}.CloneTemplate] - Template {templateName} is not replicated; use PromiseCloneTemplate`
		)
	else
		error(`[TemplateProvider.{self.ServiceName}.CloneTemplate] - Cannot provide template {templateName}`)
	end
end

--[=[
	Adds containers, observable templates, or nested declarations to the provider.

	Children of a declared container become templates. Folder templates are also
	traversed recursively. Destroy the returned task to remove the declaration.

	@within TemplateProvider
	@param declaration TemplateDeclaration
	@return MaidTask
]=]
function TemplateProvider.AddTemplates(self: TemplateProvider, declaration: TemplateDeclaration): Maid.MaidTask
	assert(self._maid, "Not initialized")
	assert(self:_isValidTemplateDeclaration(declaration), "Bad declaration")

	const registrationMaid = Maid.new()
	self._maid[registrationMaid] = registrationMaid
	self:_addTemplateDeclaration(registrationMaid, declaration)

	local isRegistered = true
	return function()
		if not isRegistered then
			return
		end

		isRegistered = false
		self._maid[registrationMaid] = nil
	end
end

--[=[
	Returns whether a loaded template is currently available.

	@within TemplateProvider
	@param templateName string
	@return boolean
]=]
function TemplateProvider.IsTemplateAvailable(self: TemplateProvider, templateName: string): boolean
	assert(type(templateName) == "string", "Bad templateName")
	assert(self._maid, "Not initialized")

	return self:_getCanonicalTemplate(self._templateEntries, templateName) ~= nil
end

--[=[
	Returns every currently loaded canonical template.

	@within TemplateProvider
	@return { Instance }
]=]
function TemplateProvider.GetTemplateList(self: TemplateProvider): { Instance }
	assert(self._maid, "Not initialized")

	const templates = {}
	for _, entries in self._templateEntries do
		const entry = entries[#entries]
		if entry then
			table.insert(templates, entry.instance)
		end
	end

	return templates
end

--[=[
	Returns every currently registered root container.

	@within TemplateProvider
	@return { Instance }
]=]
function TemplateProvider.GetContainerList(self: TemplateProvider): { Instance }
	assert(self._maid, "Not initialized")

	const containers = {}
	for container in self._containerStates do
		table.insert(containers, container)
	end

	return containers
end

TemplateProvider.IsAvailable = TemplateProvider.IsTemplateAvailable
TemplateProvider.Get = TemplateProvider.GetTemplate
TemplateProvider.Clone = TemplateProvider.CloneTemplate
TemplateProvider.PromiseClone = TemplateProvider.PromiseCloneTemplate
TemplateProvider.GetAllTemplates = TemplateProvider.GetTemplateList
TemplateProvider.GetAll = TemplateProvider.GetTemplateList

function TemplateProvider._registerServerProvider(self: TemplateProvider)
	const existingProvider = SERVER_PROVIDERS[self.ServiceName]
	assert(
		existingProvider == nil or (existingProvider :: any) == (self :: any),
		`A server TemplateProvider named {self.ServiceName} is already initialized`
	)

	SERVER_PROVIDERS[self.ServiceName] = self
	self._maid:Add(function()
		if SERVER_PROVIDERS[self.ServiceName] == self then
			SERVER_PROVIDERS[self.ServiceName] = nil
		end
	end)
end

function TemplateProvider._addTemplateDeclaration(
	self: TemplateProvider,
	topMaid: Maid.Maid,
	declaration: TemplateDeclaration
)
	if typeof(declaration) == "Instance" then
		topMaid:Add(self:_addContainer(declaration))
	elseif Observable.isObservable(declaration) then
		topMaid:Add((declaration :: Observable.Observable<Brio.Brio<Instance>>):Subscribe(function(result)
			assert(Brio.isBrio(result), "Observable template declarations must emit Brio<Instance>")
			if result:IsDead() then
				return
			end

			const brioMaid, template = result:ToMaidAndValue()
			assert(typeof(template) == "Instance", "Observable template declarations must emit Brio<Instance>")
			brioMaid:Add(self:_addAvailableTemplate(template))
		end))
	elseif type(declaration) == "table" then
		for _, childDeclaration in declaration :: { TemplateDeclaration } do
			self:_addTemplateDeclaration(topMaid, childDeclaration)
		end
	else
		error(`Bad template declaration of type {typeof(declaration)}`)
	end
end

function TemplateProvider._addContainer(self: TemplateProvider, container: Instance): () -> ()
	assert(typeof(container) == "Instance", "Bad container")

	local state = self._containerStates[container]
	if state then
		state.count += 1
	else
		const newState: ContainerState = {
			count = 1,
			maid = Maid.new(),
		}
		state = newState
		self._containerStates[container] = newState
		self:_handleContainer(newState.maid, container)
	end

	const registeredState = state :: ContainerState
	local isRegistered = true
	return function()
		if not isRegistered then
			return
		end

		isRegistered = false
		const currentState = self._containerStates[container]
		if currentState ~= registeredState then
			return
		end

		registeredState.count -= 1
		if registeredState.count <= 0 then
			self._containerStates[container] = nil
			registeredState.maid:Destroy()
		end
	end
end

function TemplateProvider._handleContainer(self: TemplateProvider, topMaid: Maid.Maid, container: Instance)
	if
		self._replicationMode == TemplateReplicationModes.SERVER
		and not container:IsA("Camera")
		and not container:FindFirstAncestorWhichIsA("Camera")
	then
		self:_handleServerContainer(topMaid, container)
		return
	end

	self:_observeChildren(topMaid, container, function(childMaid: Maid.Maid, child: Instance)
		if child:GetAttribute(TOMBSTONE_ID_ATTRIBUTE) ~= nil then
			childMaid:Add(self:_addUnreplicatedTemplate(child))
		else
			childMaid:Add(self:_addAvailableTemplate(child))
		end
	end)
end

function TemplateProvider._handleServerContainer(self: TemplateProvider, topMaid: Maid.Maid, container: Instance)
	const hiddenContainer = topMaid:Add(Instance.new("Camera"))
	hiddenContainer.Name = PREVENT_REPLICATION_NAME
	hiddenContainer.Archivable = false
	hiddenContainer.Parent = container

	local function hideChild(child: Instance)
		if child == hiddenContainer or child:GetAttribute(TOMBSTONE_ID_ATTRIBUTE) ~= nil then
			return
		end

		child.Parent = hiddenContainer
	end

	topMaid:Add(container.ChildAdded:Connect(hideChild))
	for _, child in container:GetChildren() do
		hideChild(child)
	end

	self:_observeChildren(topMaid, hiddenContainer, function(childMaid: Maid.Maid, child: Instance)
		if child:IsA("PackageLink") then
			return
		end

		childMaid:Add(self:_addAvailableTemplate(child))
		self:_createTombstoneTree(childMaid, child, container)
	end)
end

function TemplateProvider._observeChildren(
	_self: TemplateProvider,
	topMaid: Maid.Maid,
	container: Instance,
	callback: (Maid.Maid, Instance) -> ()
)
	const childMaids: { [Instance]: Maid.Maid } = {}

	local function handleChildAdded(child: Instance)
		if childMaids[child] then
			return
		end

		const childMaid = Maid.new()
		childMaids[child] = childMaid
		topMaid[child] = childMaid
		callback(childMaid, child)
	end

	local function handleChildRemoved(child: Instance)
		if not childMaids[child] then
			return
		end

		childMaids[child] = nil
		topMaid[child] = nil
	end

	topMaid:Add(container.ChildAdded:Connect(handleChildAdded))
	topMaid:Add(container.ChildRemoved:Connect(handleChildRemoved))
	for _, child in container:GetChildren() do
		handleChildAdded(child)
	end
end

function TemplateProvider._addAvailableTemplate(self: TemplateProvider, template: Instance): () -> ()
	const templateMaid = Maid.new()
	const entry: TemplateEntry = {
		instance = template,
		name = nil,
	}

	self:_moveEntry(
		self._templateEntries,
		self._templateChanged,
		self._templateNameAdded,
		self._templateNameRemoved,
		entry,
		template.Name
	)

	templateMaid:Add(template:GetPropertyChangedSignal("Name"):Connect(function()
		self:_moveEntry(
			self._templateEntries,
			self._templateChanged,
			self._templateNameAdded,
			self._templateNameRemoved,
			entry,
			template.Name
		)
	end))

	if self:_shouldAddChildrenAsTemplates(template) then
		templateMaid:Add(self:_addContainer(template))
	end

	templateMaid:Add(function()
		self:_removeEntry(
			self._templateEntries,
			self._templateChanged,
			self._templateNameAdded,
			self._templateNameRemoved,
			entry
		)
	end)

	return function()
		templateMaid:Destroy()
	end
end

function TemplateProvider._addUnreplicatedTemplate(self: TemplateProvider, tombstone: Instance): () -> ()
	const tombstoneMaid = Maid.new()
	const entry: TemplateEntry = {
		instance = tombstone,
		name = nil,
	}

	local function updateName()
		self:_moveEntry(
			self._unreplicatedTemplateEntries,
			self._unreplicatedTemplateChanged,
			self._unreplicatedTemplateNameAdded,
			self._unreplicatedTemplateNameRemoved,
			entry,
			self:_getTombstoneTemplateName(tombstone)
		)
	end

	updateName()
	tombstoneMaid:Add(tombstone:GetPropertyChangedSignal("Name"):Connect(updateName))

	if tombstone:IsA("Folder") then
		tombstoneMaid:Add(self:_addContainer(tombstone))
	end

	tombstoneMaid:Add(function()
		self:_removeEntry(
			self._unreplicatedTemplateEntries,
			self._unreplicatedTemplateChanged,
			self._unreplicatedTemplateNameAdded,
			self._unreplicatedTemplateNameRemoved,
			entry
		)
	end)

	return function()
		tombstoneMaid:Destroy()
	end
end

function TemplateProvider._createTombstoneTree(
	self: TemplateProvider,
	topMaid: Maid.Maid,
	template: Instance,
	replicatedParent: Instance
)
	const templateId = HttpService:GenerateGUID(false)
	const tombstone = topMaid:Add(Instance.new("Folder"))
	tombstone.Archivable = false
	tombstone:SetAttribute(TOMBSTONE_ID_ATTRIBUTE, templateId)

	local function updateName()
		tombstone.Name = template.Name .. TOMBSTONE_NAME_POSTFIX_UNLOADED
	end

	updateName()
	topMaid:Add(template:GetPropertyChangedSignal("Name"):Connect(updateName))

	self._tombstoneLookup[templateId] = template
	topMaid:Add(function()
		if self._tombstoneLookup[templateId] == template then
			self._tombstoneLookup[templateId] = nil
		end
	end)

	if self:_shouldAddChildrenAsTemplates(template) then
		self:_observeChildren(topMaid, template, function(childMaid: Maid.Maid, child: Instance)
			if not child:IsA("PackageLink") then
				self:_createTombstoneTree(childMaid, child, tombstone)
			end
		end)
	end

	tombstone.Parent = replicatedParent
end

function TemplateProvider._moveEntry(
	self: TemplateProvider,
	entryMap: { [string]: { TemplateEntry } },
	changedSignal: any,
	nameAddedSignal: any,
	nameRemovedSignal: any,
	entry: TemplateEntry,
	newName: string
)
	if entry.name == newName then
		return
	end

	self:_removeEntry(entryMap, changedSignal, nameAddedSignal, nameRemovedSignal, entry)

	const entries = entryMap[newName]
	const oldCanonical = if entries then entries[#entries].instance else nil
	if entries then
		table.insert(entries, entry)
	else
		entryMap[newName] = { entry }
		nameAddedSignal:Fire(newName)
	end

	entry.name = newName
	if oldCanonical ~= entry.instance then
		changedSignal:Fire(newName, entry.instance)
	end
end

function TemplateProvider._removeEntry(
	_self: TemplateProvider,
	entryMap: { [string]: { TemplateEntry } },
	changedSignal: any,
	_nameAddedSignal: any,
	nameRemovedSignal: any,
	entry: TemplateEntry
)
	const name = entry.name
	if not name then
		return
	end

	const entries = entryMap[name]
	if not entries then
		entry.name = nil
		return
	end

	const oldCanonical = entries[#entries].instance
	const index = table.find(entries, entry)
	if index then
		table.remove(entries, index)
	end

	entry.name = nil
	const newEntry = entries[#entries]
	const newCanonical = if newEntry then newEntry.instance else nil
	if not newEntry then
		entryMap[name] = nil
		nameRemovedSignal:Fire(name)
	end

	if oldCanonical ~= newCanonical then
		changedSignal:Fire(name, newCanonical)
	end
end

function TemplateProvider._observeEntry(
	self: TemplateProvider,
	entryMap: { [string]: { TemplateEntry } },
	changedSignal: any,
	templateName: string
): Observable.Observable<Instance?>
	return Observable.new(function(sub)
		const connection = changedSignal:Connect(function(changedName: string, template: Instance?)
			if changedName == templateName then
				sub:Fire(template)
			end
		end)

		sub:Fire(self:_getCanonicalTemplate(entryMap, templateName))
		return connection
	end)
end

function TemplateProvider._observeNamesBrio(
	_self: TemplateProvider,
	entryMap: { [string]: { TemplateEntry } },
	nameAddedSignal: any,
	nameRemovedSignal: any
): Observable.Observable<Brio.Brio<string>>
	return Observable.new(function(sub)
		const maid = Maid.new()
		const brios: { [string]: Brio.Brio<string> } = {}

		local function addName(name: string)
			if brios[name] then
				return
			end

			const brio = Brio.new(name)
			brios[name] = brio
			sub:Fire(brio)
		end

		local function removeName(name: string)
			const brio = brios[name]
			if brio then
				brios[name] = nil
				brio:Destroy()
			end
		end

		maid:Add(nameAddedSignal:Connect(addName))
		maid:Add(nameRemovedSignal:Connect(removeName))
		maid:Add(function()
			for name in brios do
				removeName(name)
			end
		end)

		for name in entryMap do
			addName(name)
		end

		return maid
	end)
end

function TemplateProvider._observeUnreplicatedTemplate(
	self: TemplateProvider,
	templateName: string
): Observable.Observable<Instance?>
	return self:_observeEntry(self._unreplicatedTemplateEntries, self._unreplicatedTemplateChanged, templateName)
end

function TemplateProvider._getCanonicalTemplate(
	_self: TemplateProvider,
	entryMap: { [string]: { TemplateEntry } },
	templateName: string
): Instance?
	const entries = entryMap[templateName]
	const entry = if entries then entries[#entries] else nil
	return if entry then entry.instance else nil
end

function TemplateProvider._promiseReplicateTemplateFromTombstone(
	self: TemplateProvider,
	tombstone: Instance
): Promise.Promise<Instance>
	assert(self._replicationMode == TemplateReplicationModes.CLIENT, "Only clients can request templates")

	const templateId = tombstone:GetAttribute(TOMBSTONE_ID_ATTRIBUTE)
	if type(templateId) ~= "string" then
		return Promise.rejected("Template tombstone has no valid id")
	end

	const pendingPromise = self._pendingTombstoneRequests[templateId]
	if pendingPromise then
		return pendingPromise
	end

	const promiseTemplate = Promise.spawn(function(resolve, reject)
		const invokeSuccess, responseOrError = (pcall :: any)(function(): TemplateResponse
			return TemplateProviderNetwork.queries.requestTemplate.invoke({
				providerName = self.ServiceName,
				templateId = templateId,
			})
		end)

		if not invokeSuccess then
			reject(responseOrError)
			return
		end

		const response = responseOrError :: TemplateResponse
		if not response.success then
			reject(response.errorMessage or "The server rejected the template request")
			return
		end

		const transferId = response.transferId
		if type(transferId) ~= "string" then
			reject("The server did not return a template transfer id")
			return
		end

		const cloneSuccess, cloneOrError = (pcall :: any)(function(): Instance
			const localPlayer = Players.LocalPlayer
			if not localPlayer then
				error("LocalPlayer is not available")
			end

			const playerGui = localPlayer:WaitForChild("PlayerGui", TEMPLATE_TRANSFER_TIMEOUT)
			if not playerGui then
				error("PlayerGui did not replicate in time")
			end

			const replicationContainer = playerGui:WaitForChild(REPLICATION_CONTAINER_NAME, TEMPLATE_TRANSFER_TIMEOUT)
			if not replicationContainer then
				error("Template transfer container did not replicate in time")
			end

			const temporaryTemplate = replicationContainer:WaitForChild(transferId, TEMPLATE_TRANSFER_TIMEOUT)
			if not temporaryTemplate then
				error("Template transfer did not replicate in time")
			end

			return temporaryTemplate:Clone()
		end)
		if not cloneSuccess then
			reject(cloneOrError)
			return
		end

		const clone = cloneOrError :: Instance
		clone.Name = self:_getTombstoneTemplateName(tombstone)
		resolve(clone)
	end)

	self._pendingTombstoneRequests[templateId] = promiseTemplate
	self._maid[promiseTemplate] = promiseTemplate
	promiseTemplate:Finally(function()
		self._pendingTombstoneRequests[templateId] = nil
		self._maid[promiseTemplate] = nil
	end)

	return promiseTemplate
end

function TemplateProvider._serveTemplate(self: TemplateProvider, player: Player, templateId: string): TemplateResponse
	const template = self._tombstoneLookup[templateId]
	if not template then
		return {
			success = false,
			errorMessage = "Unknown or expired template id",
			transferId = nil,
		}
	end

	const playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return {
			success = false,
			errorMessage = "PlayerGui is not available",
			transferId = nil,
		}
	end

	local replicationContainer = playerGui:FindFirstChild(REPLICATION_CONTAINER_NAME)
	if not replicationContainer then
		replicationContainer = Instance.new("Folder")
		replicationContainer.Name = REPLICATION_CONTAINER_NAME
		replicationContainer.Archivable = false
		replicationContainer.Parent = playerGui
	end

	const transferId = HttpService:GenerateGUID(false)
	const cloneSuccess, cloneOrError = (pcall :: any)(function(): Instance
		const copy = template:Clone()
		copy.Name = transferId
		copy.Parent = replicationContainer
		return copy
	end)
	if not cloneSuccess then
		return {
			success = false,
			errorMessage = tostring(cloneOrError),
			transferId = nil,
		}
	end

	const temporaryTemplate = cloneOrError :: Instance
	task.delay(TEMPORARY_TEMPLATE_LIFETIME, function()
		temporaryTemplate:Destroy()
	end)

	return {
		success = true,
		errorMessage = nil,
		transferId = transferId,
	}
end

function TemplateProvider._cloneTemplate(_self: TemplateProvider, template: Instance): Instance
	const clone = template:Clone()
	clone.Name = StringUtils.removePostfix(template.Name, "Template")
	return clone
end

function TemplateProvider._getTombstoneTemplateName(_self: TemplateProvider, tombstone: Instance): string
	if StringUtils.endsWith(tombstone.Name, TOMBSTONE_NAME_POSTFIX_UNLOADED) then
		return StringUtils.removePostfix(tombstone.Name, TOMBSTONE_NAME_POSTFIX_UNLOADED)
	elseif StringUtils.endsWith(tombstone.Name, TOMBSTONE_NAME_POSTFIX_LOADED) then
		return StringUtils.removePostfix(tombstone.Name, TOMBSTONE_NAME_POSTFIX_LOADED)
	else
		return tombstone.Name
	end
end

function TemplateProvider._shouldAddChildrenAsTemplates(_self: TemplateProvider, template: Instance): boolean
	return template:IsA("Folder")
end

function TemplateProvider._isValidTemplateDeclaration(self: TemplateProvider, declaration: TemplateDeclaration): boolean
	if typeof(declaration) == "Instance" or Observable.isObservable(declaration) then
		return true
	elseif type(declaration) == "table" then
		for _, childDeclaration in declaration :: { TemplateDeclaration } do
			if not self:_isValidTemplateDeclaration(childDeclaration) then
				return false
			end
		end
		return true
	else
		return false
	end
end

if RunService:IsRunning() and RunService:IsServer() then
	TemplateProviderNetwork.queries.requestTemplate.listen(
		function(request: TemplateRequest, player: Player?): TemplateResponse
			if typeof(player) ~= "Instance" or not player:IsA("Player") then
				return {
					success = false,
					errorMessage = "No requesting player",
					transferId = nil,
				}
			end

			const provider = SERVER_PROVIDERS[request.providerName]
			if not provider then
				return {
					success = false,
					errorMessage = `Unknown template provider {request.providerName}`,
					transferId = nil,
				}
			end

			return provider:_serveTemplate(player, request.templateId)
		end
	)
end

function TemplateProvider.Destroy(self: TemplateProvider)
	self._maid:Destroy()
end

return TemplateProvider
