--!strict
--[=[
	Coordinates client-side distance culling for tagged world Instances.

	@class ClientCullingService
	@client
]=]
const Binder = require("@game/ReplicatedStorage/Packages/Binder")
const ClientCullingConstants = require("./ClientCullingConstants")
const ClientCullingModel = require("./ClientCullingModel")
const ClientCullingRegistry = require("./ClientCullingRegistry")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const Signal = require("@game/ReplicatedStorage/Packages/Signal")
const TransparencyService = require("@game/ReplicatedStorage/Packages/TransparencyService")
const t = require("@game/ReplicatedStorage/Packages/t")

const ClientCullingService = {}
ClientCullingService.ServiceName = "ClientCullingService"
ClientCullingService.ServiceRealm = "Client"

export type ClientCullingService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_transparencyService: TransparencyService.TransparencyService,
		_registry: ClientCullingRegistry.ClientCullingRegistry,
		_cullBinder: Binder.Binder<ClientCullingModel.ClientCullingModel>,
		_shadowBinder: Binder.Binder<ClientCullingModel.ClientCullingModel>,
	},
	{} :: typeof({ __index = ClientCullingService })
))

function ClientCullingService.Init(self: ClientCullingService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._transparencyService = self._serviceBag:GetService(TransparencyService)
	self._registry = ClientCullingRegistry.new(self._transparencyService)
	self._cullBinder = Binder.new(ClientCullingConstants.CULL_TAG, function(adornee)
		return ClientCullingModel.new(adornee, "Render", self._registry)
	end)
	self._shadowBinder = Binder.new(ClientCullingConstants.CULL_SHADOWS_TAG, function(adornee)
		return ClientCullingModel.new(adornee, "Shadows", self._registry)
	end)

	self._maid._registry = self._registry
	self._maid._cullBinder = self._cullBinder
	self._maid._shadowBinder = self._shadowBinder
	self._cullBinder:Init(self._serviceBag)
	self._shadowBinder:Init(self._serviceBag)
end

function ClientCullingService.Start(self: ClientCullingService): ()
	self._registry:Start()
	self._cullBinder:Start()
	self._shadowBinder:Start()
end

--[=[
	Returns whether the `Cull` tag currently targets an Instance as hidden.

	@within ClientCullingService
	@param adornee Instance
	@return boolean
]=]
function ClientCullingService.IsCulled(self: ClientCullingService, adornee: Instance): boolean
	assert(t.Instance(adornee), "Bad adornee")
	const model = self._cullBinder:Get(adornee)
	return model ~= nil and model:IsCulled()
end

--[=[
	Returns a signal which fires when a tagged instance enters or leaves culling.

	@param adornee Instance
	@return Signal.Signal<(boolean)>?
]=]
function ClientCullingService.GetCulledChangedSignal(
	self: ClientCullingService,
	adornee: Instance
): Signal.Signal<(boolean)>?
	assert(t.Instance(adornee), "Bad adornee")
	const model = self._cullBinder:Get(adornee)
	return if model then model.CulledChanged else nil
end

--[=[
	Returns whether the `CullShadows` tag currently targets an Instance's shadows
	as hidden.

	@within ClientCullingService
	@param adornee Instance
	@return boolean
]=]
function ClientCullingService.AreShadowsCulled(self: ClientCullingService, adornee: Instance): boolean
	assert(t.Instance(adornee), "Bad adornee")
	const model = self._shadowBinder:Get(adornee)
	return model ~= nil and model:IsCulled()
end

function ClientCullingService.Destroy(self: ClientCullingService): ()
	for _, model in self._cullBinder:GetAll() do
		model:Destroy()
	end
	for _, model in self._shadowBinder:GetAll() do
		model:Destroy()
	end
	self._maid._cullBinder = nil
	self._maid._shadowBinder = nil
	self._maid._registry = nil
	self._maid:DoCleaning()
end

return ClientCullingService
