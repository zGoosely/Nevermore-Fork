--!strict
--[=[
	Resolves priority contexts and per-action restriction overlays for one local
	or server-owned actor policy.

	@class PlayerInputPolicyModel
]=]

const require = require("../../Loader").load()

const Maid = require("Maid")
const PlayerInputActionRegistryServiceShared = require("PlayerInputActionRegistryServiceShared")
const PlayerInputModeTypes = require("PlayerInputModeTypes")
const PlayerInputResults = require("PlayerInputResults")
const PlayerInputServiceConstants = require("PlayerInputServiceConstants")
const PlayerInputServiceTypes = require("PlayerInputServiceTypes")
const Signal = require("Signal")
const t = require("t")

type Action = PlayerInputServiceTypes.Action
type Context = PlayerInputServiceTypes.Context
type InputResult = PlayerInputServiceTypes.InputResult
type Restriction = PlayerInputServiceTypes.Restriction
type RestrictionConfig = PlayerInputServiceTypes.RestrictionConfig

type ActiveContext = {
	Context: Context,
	Order: number,
}

const isRestrictionConfig = t.strictInterface({
	Priority = t.number,
	Actions = t.table,
	Allowed = t.boolean,
})

const PlayerInputPolicyModel = {}
PlayerInputPolicyModel.ClassName = "PlayerInputPolicyModel"
PlayerInputPolicyModel.__index = PlayerInputPolicyModel

export type PlayerInputPolicyModel = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_registryService: PlayerInputActionRegistryServiceShared.PlayerInputActionRegistryServiceShared,
		_activeContexts: { ActiveContext },
		_restrictions: { Restriction },
		_nextOrder: number,
		Changed: Signal.Signal<()>,
	},
	{} :: typeof({ __index = PlayerInputPolicyModel })
))

function PlayerInputPolicyModel.new(
	registryService: PlayerInputActionRegistryServiceShared.PlayerInputActionRegistryServiceShared
): PlayerInputPolicyModel
	assert(t.table(registryService), "Bad registryService")

	const self = setmetatable({}, PlayerInputPolicyModel) :: PlayerInputPolicyModel
	self._maid = Maid.new()
	self._registryService = registryService
	self._activeContexts = {}
	self._restrictions = {}
	self._nextOrder = 0
	self.Changed = self._maid:Add(Signal.new())

	return self
end

--[=[
	Pushes a named context until the returned cleanup callback runs.

	@within PlayerInputPolicyModel
	@param contextName string
	@return callback
]=]
function PlayerInputPolicyModel.PushContext(self: PlayerInputPolicyModel, contextName: string): () -> ()
	assert(t.string(contextName) and contextName ~= "", "Bad contextName")

	const context = self._registryService:GetContext(contextName)
	assert(context, `Unknown context {contextName}`)

	self._nextOrder += 1
	const activeContext = {
		Context = context,
		Order = self._nextOrder,
	}
	table.insert(self._activeContexts, activeContext)
	self.Changed:Fire()

	local removed = false
	return function()
		if removed then
			return
		end
		removed = true

		const index = table.find(self._activeContexts, activeContext)
		if index then
			table.remove(self._activeContexts, index)
			self.Changed:Fire()
		end
	end
end

--[=[
	Pushes a priority action restriction until the returned cleanup callback runs.

	@within PlayerInputPolicyModel
	@param config RestrictionConfig
	@return callback
]=]
function PlayerInputPolicyModel.PushRestriction(self: PlayerInputPolicyModel, config: RestrictionConfig): () -> ()
	assert(isRestrictionConfig(config), "Bad config")
	assert(config.Priority > -math.huge and config.Priority < math.huge, "Bad config.Priority")

	const actionIds: { [number]: true } = {}
	for _, actionOrId in config.Actions do
		assert(t.number(actionOrId) or t.table(actionOrId), "Bad config.Actions")
		const actionId = if t.number(actionOrId) then actionOrId else (actionOrId :: Action).Id
		assert(t.number(actionId) and self._registryService:GetActionById(actionId), "Bad config.Actions")
		actionIds[actionId] = true
	end

	self._nextOrder += 1
	const restriction: Restriction = {
		Priority = config.Priority,
		Actions = actionIds,
		Allowed = config.Allowed,
		Order = self._nextOrder,
	}
	table.insert(self._restrictions, restriction)
	self.Changed:Fire()

	local removed = false
	return function()
		if removed then
			return
		end
		removed = true

		const index = table.find(self._restrictions, restriction)
		if index then
			table.remove(self._restrictions, index)
			self.Changed:Fire()
		end
	end
end

--[=[
	Returns whether contexts and restriction overlays permit an action.

	@within PlayerInputPolicyModel
	@param action Action
	@return boolean
]=]
function PlayerInputPolicyModel.IsActionAllowed(self: PlayerInputPolicyModel, action: Action): boolean
	return self:GetActionDenialResult(action) == nil
end

--[=[
	Returns the context or restriction result currently denying an action.

	@within PlayerInputPolicyModel
	@param action Action
	@return InputResult?
]=]
function PlayerInputPolicyModel.GetActionDenialResult(self: PlayerInputPolicyModel, action: Action): InputResult?
	assert(t.table(action), "Bad action")

	const context = self:_getCurrentContext()
	if not action.AllowedContexts[context.Name] then
		return PlayerInputResults.ContextDenied
	end

	const restriction = self:_getRestriction(action.Id)
	if restriction and not restriction.Allowed then
		return PlayerInputResults.RestrictionDenied
	end

	return nil
end

--[=[
	Returns whether policy and the last validated player input mode permit an
	action.

	@within PlayerInputPolicyModel
	@param action Action
	@param playerInputMode PlayerInputModeType?
	@return boolean
]=]
function PlayerInputPolicyModel.IsActionAllowedForPlayerMode(
	self: PlayerInputPolicyModel,
	action: Action,
	playerInputMode: PlayerInputModeTypes.PlayerInputModeType?
): boolean
	assert(t.table(action), "Bad action")
	assert(t.optional(t.string)(playerInputMode), "Bad playerInputMode")

	return playerInputMode ~= nil
		and action.AllowedPlayerInputModes[playerInputMode] == true
		and self:IsActionAllowed(action)
end

--[=[
	Returns every currently permitted replicated action ID.

	@within PlayerInputPolicyModel
	@param playerInputMode PlayerInputModeType?
	@return { number }
]=]
function PlayerInputPolicyModel.GetAllowedNetworkActionIds(
	self: PlayerInputPolicyModel,
	playerInputMode: PlayerInputModeTypes.PlayerInputModeType?
): { number }
	assert(t.optional(t.string)(playerInputMode), "Bad playerInputMode")

	const result = {}
	for _, action in self._registryService:GetActions() do
		if action.Network and self:IsActionAllowedForPlayerMode(action, playerInputMode) then
			table.insert(result, action.Id)
		end
	end
	table.sort(result)

	return result
end

--[=[
	Returns the effective context selected by priority and push order.

	@within PlayerInputPolicyModel
	@return string
]=]
function PlayerInputPolicyModel.GetCurrentContextName(self: PlayerInputPolicyModel): string
	return self:_getCurrentContext().Name
end

function PlayerInputPolicyModel._getCurrentContext(self: PlayerInputPolicyModel): Context
	local selected: ActiveContext? = nil

	for _, activeContext in self._activeContexts do
		if
			not selected
			or activeContext.Context.Priority > selected.Context.Priority
			or (activeContext.Context.Priority == selected.Context.Priority and activeContext.Order > selected.Order)
		then
			selected = activeContext
		end
	end

	if selected then
		return selected.Context
	end

	return self._registryService:GetContext(PlayerInputServiceConstants.DEFAULT_CONTEXT_NAME)
		or error("Default input context is not registered")
end

function PlayerInputPolicyModel._getRestriction(self: PlayerInputPolicyModel, actionId: number): Restriction?
	local selected: Restriction? = nil

	for _, restriction in self._restrictions do
		if
			restriction.Actions[actionId]
			and (
				not selected
				or restriction.Priority > selected.Priority
				or (restriction.Priority == selected.Priority and restriction.Order > selected.Order)
			)
		then
			selected = restriction
		end
	end

	return selected
end

function PlayerInputPolicyModel.Destroy(self: PlayerInputPolicyModel): ()
	self._maid:DoCleaning()
end

return PlayerInputPolicyModel
