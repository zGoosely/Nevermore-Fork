--!strict
--[=[
	Defines a game's semantic input actions and publishes their InputKeyMapLists
	to the existing keymap registry.

	@class PlayerInputActionProvider
]=]
const InputKeyMapList = require("@game/ReplicatedStorage/Packages/InputKeyMapList")
const InputKeyMapRegistryServiceShared = require("@game/ReplicatedStorage/Packages/InputKeyMapRegistryServiceShared")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const ObservableList = require("@game/ReplicatedStorage/Packages/ObservableList")
const PlayerInputActionRegistryServiceShared = require("./PlayerInputActionRegistryServiceShared")
const PlayerInputServiceTypes = require("./PlayerInputServiceTypes")
const PlayerInputServiceUtils = require("./PlayerInputServiceUtils")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

type Action = PlayerInputServiceTypes.Action
type ActionConfig = PlayerInputServiceTypes.ActionConfig
type Context = PlayerInputServiceTypes.Context
type CreateDefaultsCallback = PlayerInputServiceTypes.CreateDefaultsCallback

const PlayerInputActionProvider = {}
PlayerInputActionProvider.ClassName = "PlayerInputActionProvider"
PlayerInputActionProvider.__index = PlayerInputActionProvider

export type PlayerInputActionProvider = typeof(setmetatable(
	{} :: {
		ServiceName: string,
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_actionRegistryService: PlayerInputActionRegistryServiceShared.PlayerInputActionRegistryServiceShared,
		_inputKeyMapRegistryService: InputKeyMapRegistryServiceShared.InputKeyMapRegistryServiceShared,
		_providerName: string,
		_createDefaults: CreateDefaultsCallback,
		_actions: { Action },
		_actionsByName: { [string]: Action },
		_contexts: { Context },
		_contextsByName: { [string]: Context },
		_inputKeyMapLists: ObservableList.ObservableList<InputKeyMapList.InputKeyMapList>,
		_inputKeyMapListsByName: { [string]: InputKeyMapList.InputKeyMapList },
	},
	{} :: typeof({ __index = PlayerInputActionProvider })
))

function PlayerInputActionProvider.new(
	providerName: string,
	createDefaults: CreateDefaultsCallback
): PlayerInputActionProvider
	assert(t.string(providerName) and providerName ~= "", "Bad providerName")
	assert(t.callback(createDefaults), "Bad createDefaults")

	const self = setmetatable({}, PlayerInputActionProvider) :: PlayerInputActionProvider
	self.ServiceName = `PlayerInputActionProvider_{providerName}`
	self._providerName = providerName
	self._createDefaults = createDefaults

	return self
end

function PlayerInputActionProvider.Init(self: PlayerInputActionProvider, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._actionRegistryService = self._serviceBag:GetService(PlayerInputActionRegistryServiceShared)
	self._inputKeyMapRegistryService = self._serviceBag:GetService(InputKeyMapRegistryServiceShared)
	self._actions = {}
	self._actionsByName = {}
	self._contexts = {}
	self._contextsByName = {}
	self._inputKeyMapLists = self._maid:Add(ObservableList.new())
	self._inputKeyMapListsByName = {}

	self._createDefaults(self :: any, serviceBag)

	self._maid:Add(self._actionRegistryService:RegisterProvider(self :: any))
	self._maid:Add(self._inputKeyMapRegistryService:RegisterProvider(self))
end

function PlayerInputActionProvider.Start(_self: PlayerInputActionProvider): ()
	-- Definitions are complete during Init.
end

--[=[
	Adds and returns a semantic action backed by an InputKeyMapList.

	@within PlayerInputActionProvider
	@param config ActionConfig
	@return Action
]=]
function PlayerInputActionProvider.AddAction(self: PlayerInputActionProvider, config: ActionConfig): Action
	assert(t.table(config), "Bad config")

	const action = PlayerInputServiceUtils.createAction(self._providerName, config)
	assert(not self._actionsByName[action.Name], `Duplicate action name {action.Name}`)
	const inputKeyMapListName = action.InputKeyMapList:GetListName()
	assert(not self._inputKeyMapListsByName[inputKeyMapListName], `Duplicate keymap list {inputKeyMapListName}`)

	self._actionsByName[action.Name] = action
	self._inputKeyMapListsByName[inputKeyMapListName] = action.InputKeyMapList
	table.insert(self._actions, action)
	self._maid:Add(action.InputKeyMapList)
	if action.AdorneeConditionContext then
		self._maid:Add(action.AdorneeConditionContext)
	end
	self._inputKeyMapLists:Add(action.InputKeyMapList)

	return action
end

--[=[
	Adds a named priority context.

	@within PlayerInputActionProvider
	@param name string
	@param priority number
	@return Context
]=]
function PlayerInputActionProvider.AddContext(self: PlayerInputActionProvider, name: string, priority: number): Context
	assert(t.string(name) and name ~= "", "Bad name")
	assert(t.number(priority) and priority > -math.huge and priority < math.huge, "Bad priority")
	assert(not self._contextsByName[name], `Duplicate context {name}`)

	const context = table.freeze({
		Name = name,
		Priority = priority,
	})
	self._contextsByName[name] = context
	table.insert(self._contexts, context)

	return context
end

--[=[
	Returns this provider's stable name.

	@within PlayerInputActionProvider
	@return string
]=]
function PlayerInputActionProvider.GetProviderName(self: PlayerInputActionProvider): string
	return self._providerName
end

--[=[
	Returns a provider-local action.

	@within PlayerInputActionProvider
	@param actionName string
	@return Action
]=]
function PlayerInputActionProvider.GetAction(self: PlayerInputActionProvider, actionName: string): Action
	assert(t.string(actionName) and actionName ~= "", "Bad actionName")
	return self._actionsByName[actionName] or error(`Unknown action {actionName}`)
end

--[=[
	Returns every action owned by this provider.

	@within PlayerInputActionProvider
	@return { Action }
]=]
function PlayerInputActionProvider.GetActions(self: PlayerInputActionProvider): { Action }
	return table.clone(self._actions)
end

--[=[
	Returns every context declared by this provider.

	@within PlayerInputActionProvider
	@return { Context }
]=]
function PlayerInputActionProvider.GetContexts(self: PlayerInputActionProvider): { Context }
	return table.clone(self._contexts)
end

--[=[
	Finds one of this provider's InputKeyMapLists.

	@within PlayerInputActionProvider
	@param name string
	@return InputKeyMapList?
]=]
function PlayerInputActionProvider.FindInputKeyMapList(
	self: PlayerInputActionProvider,
	name: string
): InputKeyMapList.InputKeyMapList?
	assert(t.string(name) and name ~= "", "Bad name")

	return self._inputKeyMapListsByName[name]
end

--[=[
	Observes this provider's InputKeyMapLists for compatibility with
	InputKeyMapRegistryServiceShared.

	@within PlayerInputActionProvider
	@return Observable<Brio<InputKeyMapList>>
]=]
function PlayerInputActionProvider.ObserveInputKeyMapListsBrio(
	self: PlayerInputActionProvider
): Observable.Observable<any>
	return self._inputKeyMapLists:ObserveItemsBrio()
end

function PlayerInputActionProvider.Destroy(self: PlayerInputActionProvider): ()
	self._maid:DoCleaning()
end

return PlayerInputActionProvider
