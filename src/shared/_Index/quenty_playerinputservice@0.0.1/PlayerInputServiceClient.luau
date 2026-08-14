--!strict
--[=[
	Binds the local player's semantic actions, applies local and server policy,
	and sends only explicitly allowed compact action events.

	@class PlayerInputServiceClient
	@client
]=]

const Players = game:GetService("Players")
const UserInputService = game:GetService("UserInputService")
const InputKeyMapServiceClient = require("@game/ReplicatedStorage/Packages/InputKeyMapServiceClient")
const InputModeServiceClient = require("@game/ReplicatedStorage/Packages/InputModeServiceClient")
const InputModeType = require("@game/ReplicatedStorage/Packages/InputModeType")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const PlayerInputActionModel = require("./Client/PlayerInputActionModel")
const PlayerInputActionRegistryServiceShared = require("./Shared/PlayerInputActionRegistryServiceShared")
const PlayerInputModeTypes = require("@game/ReplicatedStorage/Packages/PlayerInputModeTypes")
const PlayerInputModeServiceClient = require("@game/ReplicatedStorage/Packages/PlayerInputModeServiceClient")
const PlayerInputPolicyModel = require("./Shared/PlayerInputPolicyModel")
const PlayerInputServiceConstants = require("./Shared/PlayerInputServiceConstants")
const PlayerInputServiceNetwork = require("./Shared/PlayerInputServiceNetwork")
const PlayerInputServiceTypes = require("./Shared/PlayerInputServiceTypes")
const PlayerInputServiceUtils = require("./Shared/PlayerInputServiceUtils")
const RateLimiter = require("@game/ReplicatedStorage/Packages/RateLimiter")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const Signal = require("@game/ReplicatedStorage/Packages/Signal")
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

type Action = PlayerInputServiceTypes.Action
type BindingOverride = PlayerInputServiceTypes.BindingOverride
type InputState = PlayerInputServiceTypes.InputState
type InputType = PlayerInputServiceTypes.InputType
type RestrictionConfig = PlayerInputServiceTypes.RestrictionConfig

type PendingPolicyDelta = {
	AddedActionIds: { number },
	RemovedActionIds: { number },
	ContextName: string,
}

const PlayerInputServiceClient = {}
PlayerInputServiceClient.ServiceName = "PlayerInputServiceClient"

export type PlayerInputServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_actionRegistryService: PlayerInputActionRegistryServiceShared.PlayerInputActionRegistryServiceShared,
		_inputKeyMapServiceClient: InputKeyMapServiceClient.InputKeyMapServiceClient,
		_inputModeServiceClient: InputModeServiceClient.InputModeServiceClient,
		_playerInputModeServiceClient: PlayerInputModeServiceClient.PlayerInputModeServiceClient,
		_policyModel: PlayerInputPolicyModel.PlayerInputPolicyModel,
		_actionModels: { [number]: PlayerInputActionModel.PlayerInputActionModel },
		_localBindings: { [number]: { [string]: { InputType } } },
		_serverBindingOverrides: { [number]: { [string]: { InputType } } },
		_serverAllowedActionIds: { [number]: true }?,
		_serverContextName: string?,
		_serverContextCleanup: (() -> ())?,
		_pendingPolicyDeltas: { [number]: PendingPolicyDelta },
		_playerInputMode: PlayerInputModeTypes.PlayerInputModeType?,
		_networkRateLimiters: { [number]: RateLimiter.RateLimiter },
		_networkActiveActions: { [number]: true },
		_policyRevision: number,
		_bindingRevision: number,
		_inputChanged: Signal.Signal<(Action, InputState)>,
		_destroyed: boolean,
	},
	{} :: typeof({ __index = PlayerInputServiceClient })
))

function PlayerInputServiceClient.Init(self: PlayerInputServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._actionRegistryService = self._serviceBag:GetService(PlayerInputActionRegistryServiceShared)
	self._inputKeyMapServiceClient = self._serviceBag:GetService(InputKeyMapServiceClient)
	self._inputModeServiceClient = self._serviceBag:GetService(InputModeServiceClient)
	self._playerInputModeServiceClient = self._serviceBag:GetService(PlayerInputModeServiceClient)
	self._policyModel = self._maid:Add(PlayerInputPolicyModel.new(self._actionRegistryService))
	self._actionModels = {}
	self._localBindings = {}
	self._serverBindingOverrides = {}
	self._serverAllowedActionIds = nil
	self._serverContextName = nil
	self._serverContextCleanup = nil
	self._pendingPolicyDeltas = {}
	self._playerInputMode = nil
	self._networkRateLimiters = {}
	self._networkActiveActions = {}
	self._policyRevision = 0
	self._bindingRevision = 0
	self._inputChanged = self._maid:Add(Signal.new())
	self._destroyed = false
end

function PlayerInputServiceClient.Start(self: PlayerInputServiceClient): ()
	PlayerInputServiceNetwork.packets.policyChanged.listen(function(data)
		if not self._destroyed then
			self:_applyServerPolicyDelta(data.revision, data.addedActionIds, data.removedActionIds, data.contextName)
		end
	end)
	PlayerInputServiceNetwork.packets.bindingOverrideChanged.listen(function(data)
		if not self._destroyed then
			self:_applyBindingOverride(data.revision, data.bindingOverride)
		end
	end)
	PlayerInputServiceNetwork.packets.forceRelease.listen(function(data)
		if not self._destroyed then
			self:_forceReleaseFromServer(data.actionId)
		end
	end)
	PlayerInputServiceNetwork.packets.forceReleaseAll.listen(function()
		if not self._destroyed then
			self:_forceReleaseAllFromServer()
		end
	end)

	self._maid:Add(self._actionRegistryService:ObserveActionsBrio():Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		const actionMaid, action = brio:ToMaidAndValue()
		const actionModel = PlayerInputActionModel.new(
			self._serviceBag,
			Players.LocalPlayer,
			action,
			function(candidate)
				return self:_isActionAllowed(candidate)
			end,
			function(candidate, state)
				self:_handleInput(candidate, state)
			end
		)
		self._actionModels[action.Id] = actionModel
		actionMaid:Add(actionModel)
		actionMaid:Add(function()
			if self._actionModels[action.Id] == actionModel then
				self._actionModels[action.Id] = nil
			end
		end)
	end))

	self._maid:Add(self._policyModel.Changed:Connect(function()
		self:_refreshActionPolicies()
	end))
	self._maid:Add(
		self._playerInputModeServiceClient
			:ObservePlayerInputType(Players.LocalPlayer)
			:Subscribe(function(playerInputMode)
				self._playerInputMode = playerInputMode
				self:_refreshActionPolicies()
			end)
	)
	self._maid:Add(UserInputService.TextBoxFocused:Connect(function()
		self:_refreshActionPolicies()
	end))

	self._maid:Add(task.spawn(function()
		const succeeded, initialState = pcall(PlayerInputServiceNetwork.queries.requestInitialState.invoke, nil)
		if succeeded and not self._destroyed and PlayerInputServiceUtils.isInitialState(initialState) then
			self:_applyInitialState(initialState)
		end
	end))
end

--[=[
	Observes every permitted local semantic action.

	@within PlayerInputServiceClient
	@return Observable<Action, InputState>
]=]
function PlayerInputServiceClient.ObserveAllInputs(
	self: PlayerInputServiceClient
): Observable.Observable<(Action, InputState)>
	return Observable.new(function(sub)
		return self._inputChanged:Connect(function(action, state)
			sub:Fire(action, state)
		end)
	end)
end

--[=[
	Observes one permitted local semantic action.

	@within PlayerInputServiceClient
	@param action Action
	@return Observable<InputState>
]=]
function PlayerInputServiceClient.ObserveInput(
	self: PlayerInputServiceClient,
	action: Action
): Observable.Observable<InputState>
	self:_assertRegisteredAction(action)

	return Observable.new(function(sub)
		return self._inputChanged:Connect(function(changedAction, state)
			if changedAction == action then
				sub:Fire(state)
			end
		end)
	end)
end

--[=[
	Returns whether the local player currently holds an action.

	@within PlayerInputServiceClient
	@param action Action
	@return boolean
]=]
function PlayerInputServiceClient.IsInputHeld(self: PlayerInputServiceClient, action: Action): boolean
	self:_assertRegisteredAction(action)

	const actionModel = self._actionModels[action.Id]
	return actionModel ~= nil and actionModel:IsHeld()
end

--[=[
	Observes whether the local player currently holds an action.

	@within PlayerInputServiceClient
	@param action Action
	@return Observable<boolean>
]=]
function PlayerInputServiceClient.ObserveIsInputHeld(
	self: PlayerInputServiceClient,
	action: Action
): Observable.Observable<boolean>
	self:_assertRegisteredAction(action)

	return Observable.new(function(sub)
		sub:Fire(self:IsInputHeld(action))

		return self._inputChanged:Connect(function(changedAction, state)
			if changedAction == action then
				sub:Fire(state == "Begin")
			end
		end)
	end)
end

--[=[
	Applies a local-only binding preference.

	@within PlayerInputServiceClient
	@param action Action
	@param inputModeType InputModeType
	@param inputTypes { InputType }
]=]
function PlayerInputServiceClient.SetBinding(
	self: PlayerInputServiceClient,
	action: Action,
	inputModeType: InputModeType.InputModeType,
	inputTypes: { InputType }
): ()
	self:_assertRegisteredAction(action)
	assert(t.table(inputModeType) and InputModeType.isInputModeType(inputModeType), "Bad inputModeType")
	assert(t.table(inputTypes), "Bad inputTypes")
	assert(action.InputKeyMapList:IsUserRebindable(), "Action is not user rebindable")
	assert(
		PlayerInputServiceUtils.findInputModeType(action, inputModeType.Name) == inputModeType,
		"Unknown inputModeType"
	)

	PlayerInputServiceUtils.serializeInputTypes(inputTypes)

	const bindings = self:_getOrCreateBindingMap(self._localBindings, action.Id)
	bindings[inputModeType.Name] = TableUtils.deepCopy(inputTypes)
	self:_applyEffectiveBinding(action, inputModeType)
end

--[=[
	Clears a local binding preference and restores the server override or default.

	@within PlayerInputServiceClient
	@param action Action
	@param inputModeType InputModeType
]=]
function PlayerInputServiceClient.ClearBinding(
	self: PlayerInputServiceClient,
	action: Action,
	inputModeType: InputModeType.InputModeType
): ()
	self:_assertRegisteredAction(action)
	assert(t.table(inputModeType) and InputModeType.isInputModeType(inputModeType), "Bad inputModeType")
	assert(action.InputKeyMapList:IsUserRebindable(), "Action is not user rebindable")
	assert(
		PlayerInputServiceUtils.findInputModeType(action, inputModeType.Name) == inputModeType,
		"Unknown inputModeType"
	)

	const bindings = self._localBindings[action.Id]
	if bindings then
		bindings[inputModeType.Name] = nil
	end
	self:_applyEffectiveBinding(action, inputModeType)
end

--[=[
	Restores local binding preferences for one action, or every action when
	omitted.

	@within PlayerInputServiceClient
	@param action Action?
]=]
function PlayerInputServiceClient.RestoreBindings(self: PlayerInputServiceClient, action: Action?): ()
	assert(t.optional(t.table)(action), "Bad action")

	if action then
		self:_assertRegisteredAction(action)
		self._localBindings[action.Id] = nil
		self:_applyAllEffectiveBindings(action)
		return
	end

	table.clear(self._localBindings)
	for _, registeredAction in self._actionRegistryService:GetActions() do
		self:_applyAllEffectiveBindings(registeredAction)
	end
end

--[=[
	Triggers a currently bound headless input type.

	@within PlayerInputServiceClient
	@param action Action
	@param inputType InputType
	@param state InputState
	@return boolean
]=]
function PlayerInputServiceClient.TriggerInput(
	self: PlayerInputServiceClient,
	action: Action,
	inputType: InputType,
	state: InputState
): boolean
	self:_assertRegisteredAction(action)

	const actionModel = self._actionModels[action.Id]
	return if actionModel then actionModel:TriggerInput(inputType, state) else false
end

--[=[
	Cancels every source currently holding a local action. A matching network End
	is sent when the client previously transmitted Begin for a Begin/End action.

	@within PlayerInputServiceClient
	@param action Action
	@return boolean
]=]
function PlayerInputServiceClient.ForceReleaseInput(self: PlayerInputServiceClient, action: Action): boolean
	self:_assertRegisteredAction(action)

	const actionModel = self._actionModels[action.Id]
	return actionModel ~= nil and actionModel:ForceRelease()
end

--[=[
	Cancels every locally held action and returns the number released.

	@within PlayerInputServiceClient
	@return number
]=]
function PlayerInputServiceClient.ForceReleaseAllInputs(self: PlayerInputServiceClient): number
	local released = 0

	for _, actionModel in self._actionModels do
		if actionModel:ForceRelease() then
			released += 1
		end
	end

	return released
end

--[=[
	Pushes a local priority context overlay until the returned callback is
	cleaned. Server contexts are mirrored automatically.

	@within PlayerInputServiceClient
	@param contextName string
	@return callback
]=]
function PlayerInputServiceClient.PushContext(self: PlayerInputServiceClient, contextName: string): () -> ()
	return self._policyModel:PushContext(contextName)
end

--[=[
	Pushes a local per-action restriction until the returned callback is cleaned.

	@within PlayerInputServiceClient
	@param restriction RestrictionConfig
	@return callback
]=]
function PlayerInputServiceClient.PushRestriction(
	self: PlayerInputServiceClient,
	restriction: RestrictionConfig
): () -> ()
	return self._policyModel:PushRestriction(restriction)
end

function PlayerInputServiceClient._handleInput(self: PlayerInputServiceClient, action: Action, state: InputState): ()
	if self._destroyed then
		return
	end

	self._inputChanged:Fire(action, state)

	const networkPolicy = action.Network
	if not networkPolicy then
		return
	end

	local networkState: InputState?
	if state == "Begin" and networkPolicy.States.Begin then
		if not self:_getNetworkRateLimiter(action):TryConsume() then
			return
		end
		networkState = "Begin"
		if networkPolicy.States.End then
			self._networkActiveActions[action.Id] = true
		end
	elseif (state == "End" or state == "Cancel") and networkPolicy.States.End then
		const wasNetworkActive = self._networkActiveActions[action.Id] == true
		self._networkActiveActions[action.Id] = nil
		if
			wasNetworkActive
			and (
				state == "End"
				or (self._serverAllowedActionIds ~= nil and self._serverAllowedActionIds[action.Id] == true)
			)
		then
			networkState = state
		end
	end

	if not networkState then
		return
	end

	const stateCode = PlayerInputServiceUtils.toNetworkStateCode(networkState)
	if stateCode == nil then
		return
	end

	PlayerInputServiceNetwork.packets.inputChanged.send({
		actionId = action.Id,
		state = stateCode,
	})
end

function PlayerInputServiceClient._getNetworkRateLimiter(
	self: PlayerInputServiceClient,
	action: Action
): RateLimiter.RateLimiter
	local rateLimiter = self._networkRateLimiters[action.Id]
	if rateLimiter then
		return rateLimiter
	end

	const networkPolicy = action.Network or error("Action has no network policy")
	rateLimiter = self._maid:Add(RateLimiter.new(networkPolicy.Capacity, networkPolicy.RefillRate))
	self._networkRateLimiters[action.Id] = rateLimiter
	return rateLimiter
end

function PlayerInputServiceClient._isActionAllowed(self: PlayerInputServiceClient, action: Action): boolean
	if not self._policyModel:IsActionAllowedForPlayerMode(action, self._playerInputMode) then
		return false
	end
	if not action.Network then
		return true
	end

	return self._serverAllowedActionIds ~= nil and self._serverAllowedActionIds[action.Id] == true
end

function PlayerInputServiceClient._applyServerPolicy(
	self: PlayerInputServiceClient,
	revision: number,
	allowedActionIds: { number },
	contextName: string
): ()
	if
		not t.number(revision)
		or revision < self._policyRevision
		or not t.array(t.number)(allowedActionIds)
		or not self:_isRegisteredContextName(contextName)
	then
		return
	end

	const allowedSet: { [number]: true } = {}
	for _, actionId in allowedActionIds do
		const action = self._actionRegistryService:GetActionById(actionId)
		if action and action.Network then
			allowedSet[actionId] = true
		end
	end

	self._policyRevision = revision
	self._serverAllowedActionIds = allowedSet
	for queuedRevision in self._pendingPolicyDeltas do
		if queuedRevision <= revision then
			self._pendingPolicyDeltas[queuedRevision] = nil
		end
	end

	self:_setServerContextName(contextName)
	self:_drainPendingPolicyDeltas()
	self:_refreshActionPolicies()
end

function PlayerInputServiceClient._applyServerPolicyDelta(
	self: PlayerInputServiceClient,
	revision: number,
	addedActionIds: { number },
	removedActionIds: { number },
	contextName: string
): ()
	if
		not t.number(revision)
		or revision <= self._policyRevision
		or not t.array(t.number)(addedActionIds)
		or not t.array(t.number)(removedActionIds)
		or not self:_isRegisteredContextName(contextName)
	then
		return
	end

	self._pendingPolicyDeltas[revision] = {
		AddedActionIds = table.clone(addedActionIds),
		RemovedActionIds = table.clone(removedActionIds),
		ContextName = contextName,
	}

	if self._serverAllowedActionIds then
		self:_drainPendingPolicyDeltas()
		self:_refreshActionPolicies()
	end
end

function PlayerInputServiceClient._drainPendingPolicyDeltas(self: PlayerInputServiceClient): ()
	const allowedActionIds = self._serverAllowedActionIds
	if not allowedActionIds then
		return
	end

	while true do
		const nextRevision = self._policyRevision + 1
		const delta = self._pendingPolicyDeltas[nextRevision]
		if not delta then
			return
		end

		self._pendingPolicyDeltas[nextRevision] = nil
		for _, actionId in delta.RemovedActionIds do
			allowedActionIds[actionId] = nil
		end
		for _, actionId in delta.AddedActionIds do
			const action = self._actionRegistryService:GetActionById(actionId)
			if action and action.Network then
				allowedActionIds[actionId] = true
			end
		end
		self:_setServerContextName(delta.ContextName)
		self._policyRevision = nextRevision
	end
end

function PlayerInputServiceClient._applyBindingOverride(
	self: PlayerInputServiceClient,
	revision: number,
	value: any
): ()
	if
		not t.number(revision)
		or revision < self._bindingRevision
		or not PlayerInputServiceUtils.isBindingOverride(value)
	then
		return
	end

	const bindingOverride = value :: BindingOverride
	const action = self._actionRegistryService:GetActionById(bindingOverride.ActionId)
	if not action then
		return
	end

	const inputModeType = PlayerInputServiceUtils.findInputModeType(action, bindingOverride.InputModeName)
	if not inputModeType then
		return
	end

	const overrides = self:_getOrCreateBindingMap(self._serverBindingOverrides, action.Id)
	if bindingOverride.Clear then
		overrides[inputModeType.Name] = nil
	else
		const inputTypes = PlayerInputServiceUtils.deserializeInputTypes(bindingOverride.InputTypes)
		if not inputTypes then
			return
		end
		overrides[inputModeType.Name] = inputTypes
	end

	self._bindingRevision = revision
	self:_applyEffectiveBinding(action, inputModeType)
end

function PlayerInputServiceClient._applyInitialState(
	self: PlayerInputServiceClient,
	initialState: PlayerInputServiceTypes.InitialState
): ()
	self:_applyServerPolicy(initialState.PolicyRevision, initialState.AllowedActionIds, initialState.ContextName)

	if initialState.BindingRevision < self._bindingRevision then
		return
	end

	table.clear(self._serverBindingOverrides)
	for _, bindingOverride in initialState.BindingOverrides do
		if not bindingOverride.Clear then
			const action = self._actionRegistryService:GetActionById(bindingOverride.ActionId)
			const inputTypes = PlayerInputServiceUtils.deserializeInputTypes(bindingOverride.InputTypes)
			if action and inputTypes then
				const inputModeType = PlayerInputServiceUtils.findInputModeType(action, bindingOverride.InputModeName)
				if inputModeType then
					self:_getOrCreateBindingMap(self._serverBindingOverrides, action.Id)[inputModeType.Name] =
						inputTypes
				end
			end
		end
	end

	self._bindingRevision = initialState.BindingRevision
	for _, action in self._actionRegistryService:GetActions() do
		self:_applyAllEffectiveBindings(action)
	end
end

function PlayerInputServiceClient._applyAllEffectiveBindings(self: PlayerInputServiceClient, action: Action): ()
	for _, inputKeyMap in action.InputKeyMapList:GetInputKeyMaps() do
		self:_applyEffectiveBinding(action, inputKeyMap:GetInputModeType())
	end
end

function PlayerInputServiceClient._forceReleaseFromServer(self: PlayerInputServiceClient, actionId: number): ()
	if not t.number(actionId) then
		return
	end

	const action = self._actionRegistryService:GetActionById(actionId)
	if not action then
		return
	end

	self._networkActiveActions[actionId] = nil

	const actionModel = self._actionModels[actionId]
	if actionModel then
		actionModel:ForceRelease()
	end
end

function PlayerInputServiceClient._forceReleaseAllFromServer(self: PlayerInputServiceClient): ()
	table.clear(self._networkActiveActions)

	for _, actionModel in self._actionModels do
		actionModel:ForceRelease()
	end
end

function PlayerInputServiceClient._applyEffectiveBinding(
	self: PlayerInputServiceClient,
	action: Action,
	inputModeType: InputModeType.InputModeType
): ()
	const serverOverrides = self._serverBindingOverrides[action.Id]
	const localBindings = self._localBindings[action.Id]
	const inputTypes = if serverOverrides and serverOverrides[inputModeType.Name]
		then serverOverrides[inputModeType.Name]
		elseif localBindings and localBindings[inputModeType.Name] then localBindings[inputModeType.Name]
		else action.InputKeyMapList:GetDefaultInputTypesList(inputModeType)

	action.InputKeyMapList:SetInputTypesList(inputModeType, TableUtils.deepCopy(inputTypes))
end

function PlayerInputServiceClient._getOrCreateBindingMap(
	_self: PlayerInputServiceClient,
	store: { [number]: { [string]: { InputType } } },
	actionId: number
): { [string]: { InputType } }
	local bindings = store[actionId]
	if not bindings then
		bindings = {}
		store[actionId] = bindings
	end

	return bindings
end

function PlayerInputServiceClient._refreshActionPolicies(self: PlayerInputServiceClient): ()
	for _, actionModel in self._actionModels do
		actionModel:RefreshPolicy()
	end
end

function PlayerInputServiceClient._setServerContextName(self: PlayerInputServiceClient, contextName: string): ()
	if contextName == self._serverContextName then
		return
	end

	local contextCleanup: (() -> ())? = nil
	if contextName ~= PlayerInputServiceConstants.DEFAULT_CONTEXT_NAME then
		contextCleanup = self._policyModel:PushContext(contextName)
	end

	const previousCleanup = self._serverContextCleanup
	self._serverContextName = contextName
	self._serverContextCleanup = contextCleanup
	if previousCleanup then
		previousCleanup()
	end
end

function PlayerInputServiceClient._isRegisteredContextName(self: PlayerInputServiceClient, contextName: any): boolean
	return t.string(contextName) and contextName ~= "" and self._actionRegistryService:GetContext(contextName) ~= nil
end

function PlayerInputServiceClient._assertRegisteredAction(self: PlayerInputServiceClient, action: Action): ()
	assert(t.table(action), "Bad action")
	assert(self._actionRegistryService:GetActionById(action.Id) == action, "Action is not registered")
end

function PlayerInputServiceClient.Destroy(self: PlayerInputServiceClient): ()
	self._destroyed = true
	const serverContextCleanup = self._serverContextCleanup
	self._serverContextName = nil
	self._serverContextCleanup = nil
	if serverContextCleanup then
		serverContextCleanup()
	end
	self._maid:DoCleaning()
end

return PlayerInputServiceClient
