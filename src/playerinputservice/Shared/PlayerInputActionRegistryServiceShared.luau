--!strict
--[=[
	Registers PlayerInputActionProvider instances and validates the shared action
	catalog on both realms.

	@class PlayerInputActionRegistryServiceShared
]=]

const require = require("../../Loader").load()

const Brio = require("Brio")
const Maid = require("Maid")
const Observable = require("Observable")
const ObservableList = require("ObservableList")
const PlayerInputServiceConstants = require("PlayerInputServiceConstants")
const PlayerInputServiceTypes = require("PlayerInputServiceTypes")
const PlayerInputServiceUtils = require("PlayerInputServiceUtils")
const ServiceBag = require("ServiceBag")
const t = require("t")

type Action = PlayerInputServiceTypes.Action
type Context = PlayerInputServiceTypes.Context
type ProviderLike = PlayerInputServiceTypes.ProviderLike

type ContextRecord = {
	Context: Context,
	Count: number,
}

const isProviderLike = t.interface({
	GetActions = t.callback,
	GetContexts = t.callback,
})

const PlayerInputActionRegistryServiceShared = {}
PlayerInputActionRegistryServiceShared.ServiceName = "PlayerInputActionRegistryServiceShared"

export type PlayerInputActionRegistryServiceShared = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_actionsById: { [number]: Action },
		_actionsByKey: { [string]: Action },
		_actionsList: ObservableList.ObservableList<Action>,
		_contexts: { [string]: ContextRecord },
		_providerMaids: { [ProviderLike]: Maid.Maid },
	},
	{} :: typeof({ __index = PlayerInputActionRegistryServiceShared })
))

function PlayerInputActionRegistryServiceShared.Init(
	self: PlayerInputActionRegistryServiceShared,
	serviceBag: ServiceBag.ServiceBag
): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._actionsById = {}
	self._actionsByKey = {}
	self._actionsList = self._maid:Add(ObservableList.new())
	self._contexts = {
		[PlayerInputServiceConstants.DEFAULT_CONTEXT_NAME] = {
			Context = table.freeze({
				Name = PlayerInputServiceConstants.DEFAULT_CONTEXT_NAME,
				Priority = PlayerInputServiceConstants.DEFAULT_CONTEXT_PRIORITY,
			}),
			Count = 1,
		},
	}
	self._providerMaids = {}
end

function PlayerInputActionRegistryServiceShared.Start(self: PlayerInputActionRegistryServiceShared): ()
	self:_validateCatalog()
end

--[=[
	Registers one action provider until the returned cleanup callback runs.

	@within PlayerInputActionRegistryServiceShared
	@param provider PlayerInputActionProvider
	@return callback
]=]
function PlayerInputActionRegistryServiceShared.RegisterProvider(
	self: PlayerInputActionRegistryServiceShared,
	provider: ProviderLike
): () -> ()
	assert(isProviderLike(provider), "Bad provider")
	assert(not self._providerMaids[provider], "Provider is already registered")

	const providerMaid = Maid.new()
	self._providerMaids[provider] = providerMaid

	for _, context in provider:GetContexts() do
		self:_addContext(context)
		providerMaid:Add(function()
			self:_removeContext(context)
		end)
	end

	for _, action in provider:GetActions() do
		self:_addAction(action)
		providerMaid:Add(function()
			self:_removeAction(action)
		end)
	end

	local cleaned = false
	const cleanup = function()
		if cleaned then
			return
		end
		cleaned = true

		if self._providerMaids[provider] == providerMaid then
			self._providerMaids[provider] = nil
		end
		providerMaid:DoCleaning()
	end

	self._maid[provider] = cleanup

	return function()
		self._maid[provider] = nil
	end
end

--[=[
	Returns an action by its compact global ID.

	@within PlayerInputActionRegistryServiceShared
	@param actionId number
	@return Action?
]=]
function PlayerInputActionRegistryServiceShared.GetActionById(
	self: PlayerInputActionRegistryServiceShared,
	actionId: number
): Action?
	assert(t.number(actionId), "Bad actionId")
	return self._actionsById[actionId]
end

--[=[
	Returns an action by provider and provider-local name.

	@within PlayerInputActionRegistryServiceShared
	@param providerName string
	@param actionName string
	@return Action?
]=]
function PlayerInputActionRegistryServiceShared.GetAction(
	self: PlayerInputActionRegistryServiceShared,
	providerName: string,
	actionName: string
): Action?
	assert(t.string(providerName) and providerName ~= "", "Bad providerName")
	assert(t.string(actionName) and actionName ~= "", "Bad actionName")

	return self._actionsByKey[PlayerInputServiceUtils.getActionKey(providerName, actionName)]
end

--[=[
	Returns a snapshot of every registered action.

	@within PlayerInputActionRegistryServiceShared
	@return { Action }
]=]
function PlayerInputActionRegistryServiceShared.GetActions(self: PlayerInputActionRegistryServiceShared): { Action }
	return self._actionsList:GetList()
end

--[=[
	Observes registered actions as live brios.

	@within PlayerInputActionRegistryServiceShared
	@return Observable<Brio<Action>>
]=]
function PlayerInputActionRegistryServiceShared.ObserveActionsBrio(
	self: PlayerInputActionRegistryServiceShared
): Observable.Observable<Brio.Brio<Action>>
	return self._actionsList:ObserveItemsBrio()
end

--[=[
	Returns a registered gameplay context.

	@within PlayerInputActionRegistryServiceShared
	@param contextName string
	@return Context?
]=]
function PlayerInputActionRegistryServiceShared.GetContext(
	self: PlayerInputActionRegistryServiceShared,
	contextName: string
): Context?
	assert(t.string(contextName) and contextName ~= "", "Bad contextName")

	const record = self._contexts[contextName]
	return if record then record.Context else nil
end

function PlayerInputActionRegistryServiceShared._addAction(
	self: PlayerInputActionRegistryServiceShared,
	action: Action
): ()
	const actionKey = PlayerInputServiceUtils.getActionKey(action.ProviderName, action.Name)
	assert(not self._actionsById[action.Id], `Duplicate action ID {action.Id}`)
	assert(not self._actionsByKey[actionKey], `Duplicate action {actionKey}`)

	self._actionsById[action.Id] = action
	self._actionsByKey[actionKey] = action
	self._actionsList:Add(action)
end

function PlayerInputActionRegistryServiceShared._removeAction(
	self: PlayerInputActionRegistryServiceShared,
	action: Action
): ()
	const actionKey = PlayerInputServiceUtils.getActionKey(action.ProviderName, action.Name)

	if self._actionsById[action.Id] == action then
		self._actionsById[action.Id] = nil
	end
	if self._actionsByKey[actionKey] == action then
		self._actionsByKey[actionKey] = nil
	end

	self._actionsList:RemoveFirst(action)
end

function PlayerInputActionRegistryServiceShared._addContext(
	self: PlayerInputActionRegistryServiceShared,
	context: Context
): ()
	const existing = self._contexts[context.Name]
	if existing then
		assert(existing.Context.Priority == context.Priority, `Context priority mismatch for {context.Name}`)
		existing.Count += 1
		return
	end

	self._contexts[context.Name] = {
		Context = context,
		Count = 1,
	}
end

function PlayerInputActionRegistryServiceShared._removeContext(
	self: PlayerInputActionRegistryServiceShared,
	context: Context
): ()
	const existing = self._contexts[context.Name]
	if not existing or existing.Context.Priority ~= context.Priority then
		return
	end

	existing.Count -= 1
	if existing.Count <= 0 then
		self._contexts[context.Name] = nil
	end
end

function PlayerInputActionRegistryServiceShared._validateCatalog(self: PlayerInputActionRegistryServiceShared): ()
	for _, action in self._actionsList:GetList() do
		for contextName in action.AllowedContexts do
			assert(
				self._contexts[contextName],
				`Action {action.ProviderName}.{action.Name} has unknown context {contextName}`
			)
		end

		if action.Network then
			assert(
				next(action.AllowedPlayerInputModes) ~= nil,
				`Networked action {action.ProviderName}.{action.Name} has no allowed PlayerInputMode`
			)
		end
	end
end

function PlayerInputActionRegistryServiceShared.Destroy(self: PlayerInputActionRegistryServiceShared): ()
	self._maid:DoCleaning()
end

return PlayerInputActionRegistryServiceShared
