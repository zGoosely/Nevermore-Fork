--!strict
--[=[
	Owns one Player or NPC Model's authoritative input policy, rate limiters,
	held action state, and optional player binding overrides.

	@class PlayerInputActorModel
	@server
]=]

const require = require("../../Loader").load()

const Maid = require("Maid")
const PlayerInputActorUtils = require("PlayerInputActorUtils")
const PlayerInputActionConditionModel = require("PlayerInputActionConditionModel")
const PlayerInputActionRegistryServiceShared = require("PlayerInputActionRegistryServiceShared")
const PlayerInputModeService = require("PlayerInputModeService")
const PlayerInputModeTypes = require("PlayerInputModeTypes")
const PlayerInputPolicyModel = require("PlayerInputPolicyModel")
const PlayerInputResults = require("PlayerInputResults")
const PlayerInputServiceTypes = require("PlayerInputServiceTypes")
const PlayerInputServiceUtils = require("PlayerInputServiceUtils")
const RateLimiter = require("RateLimiter")
const TableUtils = require("TableUtils")
const t = require("t")

type Action = PlayerInputServiceTypes.Action
type BindingOverride = PlayerInputServiceTypes.BindingOverride
type InitialState = PlayerInputServiceTypes.InitialState
type InputActor = PlayerInputServiceTypes.InputActor
type InputResult = PlayerInputServiceTypes.InputResult
type InputState = PlayerInputServiceTypes.InputState
type RestrictionConfig = PlayerInputServiceTypes.RestrictionConfig

export type InputCallback = (action: Action, state: InputState) -> ()
export type PolicyChangedCallback = (
	revision: number,
	addedActionIds: { number },
	removedActionIds: { number },
	contextName: string
) -> ()

const PlayerInputActorModel = {}
PlayerInputActorModel.ClassName = "PlayerInputActorModel"
PlayerInputActorModel.__index = PlayerInputActorModel

export type PlayerInputActorModel = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_actor: InputActor,
		_isPlayer: boolean,
		_registryService: PlayerInputActionRegistryServiceShared.PlayerInputActionRegistryServiceShared,
		_playerInputModeService: PlayerInputModeService.PlayerInputModeService,
		_policyModel: PlayerInputPolicyModel.PlayerInputPolicyModel,
		_conditionModels: { [number]: PlayerInputActionConditionModel.PlayerInputActionConditionModel },
		_globalRateLimiter: RateLimiter.RateLimiter,
		_actionRateLimiters: { [number]: RateLimiter.RateLimiter },
		_activeActions: { [number]: Action },
		_bindingOverrides: { [number]: { [string]: BindingOverride } },
		_playerInputMode: PlayerInputModeTypes.PlayerInputModeType?,
		_allowedActionIdSet: { [number]: true },
		_allowedActionIds: { number },
		_contextName: string,
		_policyRevision: number,
		_bindingRevision: number,
		_inputCallback: InputCallback,
		_policyChangedCallback: PolicyChangedCallback,
		_destroyed: boolean,
	},
	{} :: typeof({ __index = PlayerInputActorModel })
))

function PlayerInputActorModel.new(
	actor: InputActor,
	registryService: PlayerInputActionRegistryServiceShared.PlayerInputActionRegistryServiceShared,
	playerInputModeService: PlayerInputModeService.PlayerInputModeService,
	globalRateLimitCapacity: number,
	globalRateLimitRefillRate: number,
	inputCallback: InputCallback,
	policyChangedCallback: PolicyChangedCallback
): PlayerInputActorModel
	assert(t.Instance(actor) and PlayerInputActorUtils.isInputActor(actor), "Bad actor")
	assert(t.table(registryService), "Bad registryService")
	assert(t.table(playerInputModeService), "Bad playerInputModeService")
	assert(t.numberPositive(globalRateLimitCapacity), "Bad globalRateLimitCapacity")
	assert(t.numberPositive(globalRateLimitRefillRate), "Bad globalRateLimitRefillRate")
	assert(t.callback(inputCallback), "Bad inputCallback")
	assert(t.callback(policyChangedCallback), "Bad policyChangedCallback")

	const self = setmetatable({}, PlayerInputActorModel) :: PlayerInputActorModel
	self._maid = Maid.new()
	self._actor = actor
	self._isPlayer = actor:IsA("Player")
	self._registryService = registryService
	self._playerInputModeService = playerInputModeService
	self._policyModel = self._maid:Add(PlayerInputPolicyModel.new(registryService))
	self._conditionModels = {}
	self._globalRateLimiter = self._maid:Add(RateLimiter.new(globalRateLimitCapacity, globalRateLimitRefillRate))
	self._actionRateLimiters = {}
	self._activeActions = {}
	self._bindingOverrides = {}
	self._playerInputMode = nil
	self._allowedActionIdSet = {}
	self._allowedActionIds = {}
	self._contextName = self._policyModel:GetCurrentContextName()
	self._policyRevision = 0
	self._bindingRevision = 0
	self._inputCallback = inputCallback
	self._policyChangedCallback = policyChangedCallback
	self._destroyed = false

	self._maid:Add(self._policyModel.Changed:Connect(function()
		self:_refreshPolicy()
	end))
	if actor:IsA("Player") then
		self._maid:Add(playerInputModeService:ObservePlayerInputType(actor):Subscribe(function(playerInputMode)
			self._playerInputMode = playerInputMode
			self:_refreshPolicy()
		end))
	end
	self._maid:Add(registryService:ObserveActionsBrio():Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		const actionMaid, action = brio:ToMaidAndValue()
		const conditionModel = PlayerInputActionConditionModel.new(actor, action)
		self._conditionModels[action.Id] = conditionModel
		actionMaid:Add(conditionModel)
		actionMaid:Add(function()
			if self._conditionModels[action.Id] == conditionModel then
				self._conditionModels[action.Id] = nil
			end
		end)
	end))

	return self
end

--[=[
	Processes one compact client action event. Rejections remain silent on the
	network boundary.

	@within PlayerInputActorModel
	@param actionId number
	@param stateCode number
]=]
function PlayerInputActorModel.ProcessInput(self: PlayerInputActorModel, actionId: number, stateCode: number): ()
	assert(t.number(actionId), "Bad actionId")
	assert(t.number(stateCode), "Bad stateCode")

	if self._destroyed then
		return
	end

	const state = PlayerInputServiceUtils.fromNetworkStateCode(stateCode)
	const isClosingActiveAction = (state == "End" or state == "Cancel") and self._activeActions[actionId] ~= nil
	if not isClosingActiveAction and not self._globalRateLimiter:TryConsume() then
		return
	end

	const action = self._registryService:GetActionById(actionId)
	if not action or not state then
		return
	end

	self:_tryInput(action, state, false)
end

--[=[
	Attempts one authoritative input state for this actor and returns its result.

	@within PlayerInputActorModel
	@param action Action
	@param state InputState
	@return InputResult
]=]
function PlayerInputActorModel.TryInput(self: PlayerInputActorModel, action: Action, state: InputState): InputResult
	assert(t.table(action), "Bad action")
	assert(t.string(state) and (state == "Begin" or state == "End" or state == "Cancel"), "Bad state")

	if self._destroyed then
		return PlayerInputResults.ActorNotRegistered
	end

	return self:_tryInput(action, state, true)
end

--[=[
	Pushes an authoritative context for this actor.

	@within PlayerInputActorModel
	@param contextName string
	@return callback
]=]
function PlayerInputActorModel.PushContext(self: PlayerInputActorModel, contextName: string): () -> ()
	return self._policyModel:PushContext(contextName)
end

--[=[
	Pushes an authoritative action restriction for this actor.

	@within PlayerInputActorModel
	@param restriction RestrictionConfig
	@return callback
]=]
function PlayerInputActorModel.PushRestriction(self: PlayerInputActorModel, restriction: RestrictionConfig): () -> ()
	return self._policyModel:PushRestriction(restriction)
end

--[=[
	Returns whether the server has accepted a Begin without its matching End for
	this action.

	@within PlayerInputActorModel
	@param action Action
	@return boolean
]=]
function PlayerInputActorModel.IsInputHeld(self: PlayerInputActorModel, action: Action): boolean
	assert(t.table(action), "Bad action")
	return not self._destroyed and self._activeActions[action.Id] == action
end

--[=[
	Cancels an accepted held action.

	@within PlayerInputActorModel
	@param action Action
	@return boolean
]=]
function PlayerInputActorModel.ForceRelease(self: PlayerInputActorModel, action: Action): boolean
	assert(t.table(action), "Bad action")

	if self._destroyed or self._activeActions[action.Id] ~= action then
		return false
	end

	self._activeActions[action.Id] = nil
	self._inputCallback(action, "Cancel")
	return true
end

--[=[
	Cancels every accepted held action and returns the number released.

	@within PlayerInputActorModel
	@return number
]=]
function PlayerInputActorModel.ForceReleaseAll(self: PlayerInputActorModel): number
	if self._destroyed then
		return 0
	end

	const activeActions = table.clone(self._activeActions)
	table.clear(self._activeActions)

	for _, action in activeActions do
		self._inputCallback(action, "Cancel")
	end

	local released = 0
	for _ in activeActions do
		released += 1
	end

	return released
end

--[=[
	Stores a server binding override and returns its wire record and revision.

	@within PlayerInputActorModel
	@param action Action
	@param inputModeName string
	@param serializedInputTypes { SerializedInputType }
	@return BindingOverride
	@return number
]=]
function PlayerInputActorModel.SetBindingOverride(
	self: PlayerInputActorModel,
	action: Action,
	inputModeName: string,
	serializedInputTypes: { PlayerInputServiceTypes.SerializedInputType }
): (BindingOverride, number)
	assert(t.table(action), "Bad action")
	assert(t.string(inputModeName) and inputModeName ~= "", "Bad inputModeName")
	assert(t.table(serializedInputTypes), "Bad serializedInputTypes")
	assert(PlayerInputServiceUtils.deserializeInputTypes(serializedInputTypes) ~= nil, "Bad serializedInputTypes")

	self._bindingRevision += 1
	const bindingOverride: BindingOverride = {
		ActionId = action.Id,
		InputModeName = inputModeName,
		InputTypes = TableUtils.deepCopy(serializedInputTypes),
		Clear = false,
	}

	local actionOverrides = self._bindingOverrides[action.Id]
	if not actionOverrides then
		actionOverrides = {}
		self._bindingOverrides[action.Id] = actionOverrides
	end
	actionOverrides[inputModeName] = bindingOverride

	return PlayerInputServiceUtils.copyBindingOverride(bindingOverride), self._bindingRevision
end

--[=[
	Clears one server binding override and returns its wire record when changed.

	@within PlayerInputActorModel
	@param action Action
	@param inputModeName string
	@return BindingOverride?
	@return number
]=]
function PlayerInputActorModel.ClearBindingOverride(
	self: PlayerInputActorModel,
	action: Action,
	inputModeName: string
): (BindingOverride?, number)
	assert(t.table(action), "Bad action")
	assert(t.string(inputModeName) and inputModeName ~= "", "Bad inputModeName")

	const actionOverrides = self._bindingOverrides[action.Id]
	if not actionOverrides or not actionOverrides[inputModeName] then
		return nil, self._bindingRevision
	end

	actionOverrides[inputModeName] = nil
	if next(actionOverrides) == nil then
		self._bindingOverrides[action.Id] = nil
	end

	self._bindingRevision += 1
	return {
		ActionId = action.Id,
		InputModeName = inputModeName,
		InputTypes = {},
		Clear = true,
	},
		self._bindingRevision
end

--[=[
	Returns the complete state required by a newly started client.

	@within PlayerInputActorModel
	@return InitialState
]=]
function PlayerInputActorModel.GetInitialState(self: PlayerInputActorModel): InitialState
	const bindingOverrides = {}
	for _, actionOverrides in self._bindingOverrides do
		for _, bindingOverride in actionOverrides do
			table.insert(bindingOverrides, PlayerInputServiceUtils.copyBindingOverride(bindingOverride))
		end
	end

	return {
		AllowedActionIds = table.clone(self._allowedActionIds),
		BindingOverrides = bindingOverrides,
		ContextName = self._contextName,
		PolicyRevision = self._policyRevision,
		BindingRevision = self._bindingRevision,
	}
end

function PlayerInputActorModel._refreshPolicy(self: PlayerInputActorModel): ()
	if self._destroyed then
		return
	end

	for actionId, action in self._activeActions do
		if self:_getPolicyDenialResult(action) then
			self._activeActions[actionId] = nil
			self._inputCallback(action, "Cancel")
		end
	end

	const contextName = self._policyModel:GetCurrentContextName()
	const didContextChange = contextName ~= self._contextName
	self._contextName = contextName
	if not self._isPlayer then
		return
	end

	const allowedActionIds = self._policyModel:GetAllowedNetworkActionIds(self._playerInputMode)
	const allowedActionIdSet, addedActionIds, removedActionIds =
		PlayerInputServiceUtils.diffActionIds(self._allowedActionIdSet, allowedActionIds)
	self._allowedActionIdSet = allowedActionIdSet
	self._allowedActionIds = allowedActionIds

	if #addedActionIds == 0 and #removedActionIds == 0 and not didContextChange then
		return
	end

	self._policyRevision += 1
	self._policyChangedCallback(self._policyRevision, addedActionIds, removedActionIds, contextName)
end

function PlayerInputActorModel._tryInput(
	self: PlayerInputActorModel,
	action: Action,
	state: InputState,
	consumeGlobalRateLimit: boolean
): InputResult
	if self._registryService:GetActionById(action.Id) ~= action then
		return PlayerInputResults.ActionNotRegistered
	end

	const networkPolicy = action.Network
	if not networkPolicy then
		return PlayerInputResults.ActionNotServerEnabled
	end
	if
		(state == "Cancel" and not networkPolicy.States.End)
		or (state ~= "Cancel" and not networkPolicy.States[state])
	then
		return PlayerInputResults.StateNotAllowed
	end

	const isClosingActiveAction = (state == "End" or state == "Cancel") and self._activeActions[action.Id] ~= nil
	if consumeGlobalRateLimit and not isClosingActiveAction and not self._globalRateLimiter:TryConsume() then
		return PlayerInputResults.RateLimited
	end

	const policyDenialResult = self:_getPolicyDenialResult(action)
	if policyDenialResult then
		return policyDenialResult
	end
	if state == "Begin" and not self:_areActionConditionsMet(action) then
		return PlayerInputResults.ConditionFailed
	end
	if state == "Begin" and not self:_getActionRateLimiter(action):TryConsume() then
		return PlayerInputResults.RateLimited
	end

	if networkPolicy.States.End then
		if state == "Begin" then
			if self._activeActions[action.Id] then
				return PlayerInputResults.AlreadyHeld
			end
			self._activeActions[action.Id] = action
		else
			if not self._activeActions[action.Id] then
				return PlayerInputResults.NotHeld
			end
			self._activeActions[action.Id] = nil
		end
	elseif state ~= "Begin" then
		return PlayerInputResults.StateNotAllowed
	end

	self._inputCallback(action, state)
	return PlayerInputResults.Accepted
end

function PlayerInputActorModel._getPolicyDenialResult(self: PlayerInputActorModel, action: Action): InputResult?
	const policyDenialResult = self._policyModel:GetActionDenialResult(action)
	if policyDenialResult then
		return policyDenialResult
	end

	if
		self._isPlayer
		and (self._playerInputMode == nil or action.AllowedPlayerInputModes[self._playerInputMode] ~= true)
	then
		return PlayerInputResults.InputModeDenied
	end

	return nil
end

function PlayerInputActorModel._areActionConditionsMet(self: PlayerInputActorModel, action: Action): boolean
	if not action.AdorneeConditionContext then
		return true
	end

	const conditionModel = self._conditionModels[action.Id]
	return conditionModel ~= nil and conditionModel:AreConditionsMet()
end

function PlayerInputActorModel._getActionRateLimiter(
	self: PlayerInputActorModel,
	action: Action
): RateLimiter.RateLimiter
	local rateLimiter = self._actionRateLimiters[action.Id]
	if rateLimiter then
		return rateLimiter
	end

	const networkPolicy = action.Network or error("Action has no network policy")
	rateLimiter = self._maid:Add(RateLimiter.new(networkPolicy.Capacity, networkPolicy.RefillRate))
	self._actionRateLimiters[action.Id] = rateLimiter
	return rateLimiter
end

function PlayerInputActorModel.Destroy(self: PlayerInputActorModel): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	const activeActions = table.clone(self._activeActions)
	table.clear(self._activeActions)
	for _, action in activeActions do
		self._inputCallback(action, "Cancel")
	end

	self._maid:DoCleaning()
end

return PlayerInputActorModel
