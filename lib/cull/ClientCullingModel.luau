--!strict
--!optimize 2
--[=[
	Owns one tagged Instance's configuration, cached bounds, and culling state.

	@class ClientCullingModel
	@client
]=]

const require = require("../Loader").load()

const ClientCullingConstants = require("ClientCullingConstants")
const ClientCullingRegistry = require("ClientCullingRegistry")
const ClientCullingTypes = require("ClientCullingTypes")
const ClientCullingUtils = require("ClientCullingUtils")
const Maid = require("Maid")
const t = require("t")

type CullBounds = ClientCullingTypes.CullBounds
type CullConfig = ClientCullingTypes.CullConfig
type CullMode = ClientCullingTypes.CullMode

const ClientCullingModel = {}
ClientCullingModel.ClassName = "ClientCullingModel"
ClientCullingModel.__index = ClientCullingModel

export type ClientCullingModel = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_adornee: Instance,
		_mode: CullMode,
		_registry: ClientCullingRegistry.ClientCullingRegistry,
		_config: CullConfig,
		_bounds: CullBounds,
		_culled: boolean,
		_queryGeneration: number,
		_registered: boolean,
		_destroyed: boolean,
		_boundsRefreshQueued: boolean,
		_pivotToBounds: CFrame?,
		_lastWarning: string?,
	},
	{} :: typeof({ __index = ClientCullingModel })
))

function ClientCullingModel.new(
	adornee: Instance,
	mode: CullMode,
	registry: ClientCullingRegistry.ClientCullingRegistry
): ClientCullingModel
	assert(t.Instance(adornee), "Bad adornee")
	assert(t.literal("Render", "Shadows")(mode), "Bad mode")
	assert(t.table(registry), "Bad registry")

	const self = setmetatable({}, ClientCullingModel) :: ClientCullingModel
	self._maid = Maid.new()
	self._adornee = adornee
	self._mode = mode
	self._registry = registry
	self._config = {
		CullDistance = ClientCullingConstants.DEFAULT_CULL_DISTANCE,
		UncullDistance = ClientCullingConstants.DEFAULT_CULL_DISTANCE,
		Dynamic = false,
	}
	self._bounds = {
		CFrame = CFrame.identity,
		Size = Vector3.zero,
		Radius = 0,
	}
	self._culled = false
	self._queryGeneration = 0
	self._registered = false
	self._destroyed = false
	self._boundsRefreshQueued = false
	self._pivotToBounds = nil
	self._lastWarning = nil

	for _, attributeName in
		{
			ClientCullingConstants.CULL_DISTANCE_ATTRIBUTE,
			ClientCullingConstants.CULL_UNCULL_DISTANCE_ATTRIBUTE,
			ClientCullingConstants.CULL_DYNAMIC_ATTRIBUTE,
		}
	do
		self._maid:Add(adornee:GetAttributeChangedSignal(attributeName):Connect(function()
			self:_refreshRegistration(false)
		end))
	end

	self._maid:Add(adornee.DescendantAdded:Connect(function(descendant)
		self._registry:AddDescendant(self :: any, descendant)
		self:_queueBoundsRefresh()
	end))
	self._maid:Add(adornee.DescendantRemoving:Connect(function(descendant)
		self._registry:RemoveDescendant(self :: any, descendant)
		self:_queueBoundsRefresh()
	end))

	self:_refreshRegistration(true)
	return self
end

--[=[
	Returns whether this tag currently targets the Instance for culling.

	@within ClientCullingModel
	@return boolean
]=]
function ClientCullingModel.IsCulled(self: ClientCullingModel): boolean
	return self._culled
end

--[=[
	Refreshes cached movement without recomputing a Model's complete bounds.

	@within ClientCullingModel
	@return boolean
]=]
function ClientCullingModel.RefreshDynamicBounds(self: ClientCullingModel): boolean
	if self._destroyed or not self._registered then
		return false
	end

	if self._adornee:IsA("Model") and self._pivotToBounds then
		self._bounds.CFrame = self._adornee:GetPivot() * self._pivotToBounds
		return true
	elseif self._adornee:IsA("BasePart") then
		self._bounds.CFrame = self._adornee.CFrame
		if self._bounds.Size ~= self._adornee.Size then
			self._bounds.Size = self._adornee.Size
			self._bounds.Radius = self._adornee.Size.Magnitude * 0.5
		end
		return true
	end

	const bounds = ClientCullingUtils.deriveBounds(self._adornee)
	if not bounds then
		return false
	end
	self._bounds = bounds
	return true
end

--[=[
	Updates this entry's target state and queues the corresponding render work.

	@within ClientCullingModel
	@param culled boolean
]=]
function ClientCullingModel.SetCulled(self: ClientCullingModel, culled: boolean): ()
	assert(t.boolean(culled), "Bad culled")
	if self._culled == culled then
		return
	end

	self._culled = culled
	self._registry:SetEntryCulled(self :: any, culled)
end

function ClientCullingModel._queueBoundsRefresh(self: ClientCullingModel): ()
	if self._destroyed or self._boundsRefreshQueued then
		return
	end
	self._boundsRefreshQueued = true
	task.defer(function()
		if self._destroyed then
			return
		end
		self._boundsRefreshQueued = false
		self:_refreshRegistration(true)
	end)
end

function ClientCullingModel._refreshRegistration(self: ClientCullingModel, rebuildBounds: boolean): ()
	const config, configError = ClientCullingUtils.getConfig(self._adornee)
	if not config then
		self:_invalidate(configError or "Invalid culling configuration")
		return
	end

	local bounds = if rebuildBounds or not self._registered
		then ClientCullingUtils.deriveBounds(self._adornee)
		else self._bounds
	if not bounds then
		self:_invalidate("Unable to derive culling bounds")
		return
	end

	self._lastWarning = nil
	self._config = config
	self._bounds = bounds
	if self._adornee:IsA("Model") then
		self._pivotToBounds = self._adornee:GetPivot():ToObjectSpace(bounds.CFrame)
	else
		self._pivotToBounds = nil
	end

	if self._registered then
		self._registry:UpdateEntry(self :: any)
	else
		self._registered = true
		self._registry:AddEntry(self :: any)
	end
end

function ClientCullingModel._invalidate(self: ClientCullingModel, reason: string): ()
	if self._lastWarning ~= reason then
		self._lastWarning = reason
		warn(`[ClientCulling] {self._adornee:GetFullName()}: {reason}`)
	end

	if self._registered then
		self._registered = false
		self._registry:RemoveEntry(self :: any)
	end
end

function ClientCullingModel.Destroy(self: ClientCullingModel): ()
	self._destroyed = true
	if self._registered then
		self._registered = false
		self._registry:RemoveEntry(self :: any)
	end
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return ClientCullingModel
