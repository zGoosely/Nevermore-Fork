--!strict
--[=[
	Validates compact semantic input reports and provides authoritative contexts,
	restrictions, server binding overrides, and input observations.

	@class PlayerInputService
	@server
]=]
const Brio = require("@game/ReplicatedStorage/Packages/Brio")
const InputModeType = require("@game/ReplicatedStorage/Packages/InputModeType")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const ObservableSet = require("@game/ReplicatedStorage/Packages/ObservableSet")
const PlayerInputActorModel = require("./Server/PlayerInputActorModel")
const PlayerInputActorUtils = require("./Shared/PlayerInputActorUtils")
const PlayerInputActionRegistryServiceShared = require("./Shared/PlayerInputActionRegistryServiceShared")
const PlayerInputModeService = require("@game/ReplicatedStorage/Packages/PlayerInputModeService")
const PlayerInputResults = require("./Shared/PlayerInputResults")
const PlayerInputServiceConstants = require("./Shared/PlayerInputServiceConstants")
const PlayerInputServiceNetwork = require("./Shared/PlayerInputServiceNetwork")
const PlayerInputServiceTypes = require("./Shared/PlayerInputServiceTypes")
const PlayerInputServiceUtils = require("./Shared/PlayerInputServiceUtils")
const RxPlayerUtils = require("@game/ReplicatedStorage/Packages/RxPlayerUtils")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const Signal = require("@game/ReplicatedStorage/Packages/Signal")
const t = require("@game/ReplicatedStorage/Packages/t")

type Action = PlayerInputServiceTypes.Action
type InputActor = PlayerInputServiceTypes.InputActor
type InputResult = PlayerInputServiceTypes.InputResult
type InputState = PlayerInputServiceTypes.InputState
type InputType = PlayerInputServiceTypes.InputType
type RestrictionConfig = PlayerInputServiceTypes.RestrictionConfig

type ActorRecord = {
	Maid: Maid.Maid,
	Model: PlayerInputActorModel.PlayerInputActorModel,
	RefCount: number,
}

const PlayerInputService = {}
PlayerInputService.ServiceName = "PlayerInputService"
PlayerInputService.ServerOnly = true

export type PlayerInputService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_actionRegistryService: PlayerInputActionRegistryServiceShared.PlayerInputActionRegistryServiceShared,
		_playerInputModeService: PlayerInputModeService.PlayerInputModeService,
		_actorRecords: { [InputActor]: ActorRecord },
		_actors: ObservableSet.ObservableSet<InputActor>,
		_globalRateLimitCapacity: number,
		_globalRateLimitRefillRate: number,
		_inputChanged: Signal.Signal<(InputActor, Action, InputState)>,
		_started: boolean,
		_destroyed: boolean,
	},
	{} :: typeof({ __index = PlayerInputService })
))

function PlayerInputService.Init(self: PlayerInputService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._actionRegistryService = self._serviceBag:GetService(PlayerInputActionRegistryServiceShared)
	self._playerInputModeService = self._serviceBag:GetService(PlayerInputModeService)
	self._actorRecords = {}
	self._actors = self._maid:Add(ObservableSet.new())
	self._globalRateLimitCapacity = PlayerInputServiceConstants.DEFAULT_GLOBAL_RATE_LIMIT_CAPACITY
	self._globalRateLimitRefillRate = PlayerInputServiceConstants.DEFAULT_GLOBAL_RATE_LIMIT_REFILL_RATE
	self._inputChanged = self._maid:Add(Signal.new())
	self._started = false
	self._destroyed = false
end

function PlayerInputService.Start(self: PlayerInputService): ()
	self._started = true

	PlayerInputServiceNetwork.packets.inputChanged.listen(function(data, player)
		if self._destroyed or not player then
			return
		end

		const actorRecord = self._actorRecords[player]
		if actorRecord then
			actorRecord.Model:ProcessInput(data.actionId, data.state)
		end
	end)

	PlayerInputServiceNetwork.queries.requestInitialState.listen(function(_request, player)
		if self._destroyed or not player then
			return nil
		end

		const actorRecord = self._actorRecords[player]
		return if actorRecord then actorRecord.Model:GetInitialState() else nil
	end)

	self._maid:Add(RxPlayerUtils.observePlayersBrio():Subscribe(function(brio)
		const playerMaid, player = brio:ToMaidAndValue()
		playerMaid:Add(self:RegisterActor(player))
	end))
end

--[=[
	Registers a Player or Humanoid NPC Model until the returned callback is
	cleaned. Players are registered automatically.

	@within PlayerInputService
	@param actor InputActor
	@return callback
]=]
function PlayerInputService.RegisterActor(self: PlayerInputService, actor: InputActor): () -> ()
	assert(t.Instance(actor) and PlayerInputActorUtils.isInputActor(actor), "Bad actor")
	assert(not self._destroyed, "PlayerInputService is destroyed")

	local actorRecord = self._actorRecords[actor]
	if not actorRecord then
		const actorMaid = Maid.new()
		const actorModel = PlayerInputActorModel.new(
			actor,
			self._actionRegistryService,
			self._playerInputModeService,
			self._globalRateLimitCapacity,
			self._globalRateLimitRefillRate,
			function(action, state)
				if not self._destroyed then
					self._inputChanged:Fire(actor, action, state)
				end
			end,
			function(revision, addedActionIds, removedActionIds, contextName)
				if actor:IsA("Player") then
					PlayerInputServiceNetwork.packets.policyChanged.sendTo({
						revision = revision,
						addedActionIds = addedActionIds,
						removedActionIds = removedActionIds,
						contextName = contextName,
					}, actor)
				end
			end
		)

		const createdRecord: ActorRecord = {
			Maid = actorMaid,
			Model = actorModel,
			RefCount = 0,
		}
		actorRecord = createdRecord
		self._actorRecords[actor] = createdRecord
		self._maid[actorMaid] = actorMaid
		actorMaid:Add(actorModel)
		actorMaid:Add(actor.Destroying:Connect(function()
			self:_removeActorRecord(actor, createdRecord)
		end))
		if actor:IsA("Model") then
			const humanoid = actor:FindFirstChildWhichIsA("Humanoid")
			assert(humanoid, "Registered NPC actor has no Humanoid")
			actorMaid:Add(humanoid.Destroying:Connect(function()
				self:_removeActorRecord(actor, createdRecord)
			end))
		end
		actorMaid:Add(self._actors:Add(actor))
	end

	actorRecord.RefCount += 1
	const registeredRecord = actorRecord
	local isCleaned = false
	return function()
		if isCleaned then
			return
		end
		isCleaned = true

		if self._actorRecords[actor] ~= registeredRecord then
			return
		end

		registeredRecord.RefCount -= 1
		if registeredRecord.RefCount <= 0 then
			self:_removeActorRecord(actor, registeredRecord)
		end
	end
end

--[=[
	Observes registered Players and Humanoid NPC Models for their complete
	authoritative input lifetime.

	@within PlayerInputService
	@return Observable<Brio<InputActor>>
]=]
function PlayerInputService.ObserveActorsBrio(self: PlayerInputService): Observable.Observable<Brio.Brio<InputActor>>
	return self._actors:ObserveItemsBrio()
end

--[=[
	Configures the per-actor global server input guard before the service starts.

	@within PlayerInputService
	@param capacity number
	@param refillRate number
]=]
function PlayerInputService.SetGlobalServerInputRateLimit(
	self: PlayerInputService,
	capacity: number,
	refillRate: number
): ()
	assert(t.numberPositive(capacity), "Bad capacity")
	assert(t.numberPositive(refillRate), "Bad refillRate")
	assert(capacity < math.huge, "Bad capacity")
	assert(refillRate < math.huge, "Bad refillRate")
	assert(not self._started, "Cannot configure server input rate limit after Start")

	self._globalRateLimitCapacity = capacity
	self._globalRateLimitRefillRate = refillRate
end

--[=[
	Configures the per-player packet guard before the service starts. This is a
	compatibility alias for `SetGlobalServerInputRateLimit`.

	@within PlayerInputService
	@param capacity number
	@param refillRate number
]=]
function PlayerInputService.SetGlobalNetworkRateLimit(
	self: PlayerInputService,
	capacity: number,
	refillRate: number
): ()
	self:SetGlobalServerInputRateLimit(capacity, refillRate)
end

--[=[
	Observes every accepted Player or NPC actor action.

	@within PlayerInputService
	@return Observable<InputActor, Action, InputState>
]=]
function PlayerInputService.ObserveAllInputs(
	self: PlayerInputService
): Observable.Observable<(InputActor, Action, InputState)>
	return Observable.new(function(sub)
		return self._inputChanged:Connect(function(actor, action, state)
			sub:Fire(actor, action, state)
		end)
	end)
end

--[=[
	Observes one accepted action across every Player and NPC actor.

	@within PlayerInputService
	@param action Action
	@return Observable<InputActor, InputState>
]=]
function PlayerInputService.ObserveInput(
	self: PlayerInputService,
	action: Action
): Observable.Observable<(InputActor, InputState)>
	self:_assertRegisteredAction(action)

	return Observable.new(function(sub)
		return self._inputChanged:Connect(function(actor, changedAction, state)
			if changedAction == action then
				sub:Fire(actor, state)
			end
		end)
	end)
end

--[=[
	Attempts one authoritative action state for a registered actor.

	@within PlayerInputService
	@param actor InputActor
	@param action Action
	@param state InputState
	@return InputResult
]=]
function PlayerInputService.TriggerActorInput(
	self: PlayerInputService,
	actor: InputActor,
	action: Action,
	state: InputState
): InputResult
	assert(t.Instance(actor) and PlayerInputActorUtils.isInputActor(actor), "Bad actor")
	assert(t.table(action), "Bad action")
	assert(t.string(state) and (state == "Begin" or state == "End" or state == "Cancel"), "Bad state")

	const actorRecord = self._actorRecords[actor]
	if not actorRecord then
		return PlayerInputResults.ActorNotRegistered
	end

	return actorRecord.Model:TryInput(action, state)
end

--[=[
	Observes one accepted action for one actor.

	@within PlayerInputService
	@param actor InputActor
	@param action Action
	@return Observable<InputState>
]=]
function PlayerInputService.ObserveActorInput(
	self: PlayerInputService,
	actor: InputActor,
	action: Action
): Observable.Observable<InputState>
	assert(t.Instance(actor) and PlayerInputActorUtils.isInputActor(actor), "Bad actor")
	self:_assertRegisteredAction(action)

	return Observable.new(function(sub)
		return self._inputChanged:Connect(function(changedActor, changedAction, state)
			if changedActor == actor and changedAction == action then
				sub:Fire(state)
			end
		end)
	end)
end

--[=[
	Observes one accepted action for one player.

	@within PlayerInputService
	@param player Player
	@param action Action
	@return Observable<InputState>
]=]
function PlayerInputService.ObservePlayerInput(
	self: PlayerInputService,
	player: Player,
	action: Action
): Observable.Observable<InputState>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:ObserveActorInput(player, action)
end

--[=[
	Returns whether the server currently considers an actor's action held.

	@within PlayerInputService
	@param actor InputActor
	@param action Action
	@return boolean
]=]
function PlayerInputService.IsActorInputHeld(self: PlayerInputService, actor: InputActor, action: Action): boolean
	self:_assertRegisteredAction(action)
	return self:_getActorModel(actor):IsInputHeld(action)
end

--[=[
	Returns whether the server currently considers a player's action held.

	@within PlayerInputService
	@param player Player
	@param action Action
	@return boolean
]=]
function PlayerInputService.IsPlayerInputHeld(self: PlayerInputService, player: Player, action: Action): boolean
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:IsActorInputHeld(player, action)
end

--[=[
	Observes whether the server currently considers an actor's action held.

	@within PlayerInputService
	@param actor InputActor
	@param action Action
	@return Observable<boolean>
]=]
function PlayerInputService.ObserveIsActorInputHeld(
	self: PlayerInputService,
	actor: InputActor,
	action: Action
): Observable.Observable<boolean>
	self:_assertRegisteredAction(action)
	const actorModel = self:_getActorModel(actor)

	return Observable.new(function(sub)
		sub:Fire(actorModel:IsInputHeld(action))

		return self._inputChanged:Connect(function(changedActor, changedAction, state)
			if changedActor == actor and changedAction == action then
				sub:Fire(state == "Begin")
			end
		end)
	end)
end

--[=[
	Observes whether the server currently considers a player's action held.

	@within PlayerInputService
	@param player Player
	@param action Action
	@return Observable<boolean>
]=]
function PlayerInputService.ObserveIsPlayerInputHeld(
	self: PlayerInputService,
	player: Player,
	action: Action
): Observable.Observable<boolean>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:ObserveIsActorInputHeld(player, action)
end

--[=[
	Pushes an authoritative actor context until the returned callback is cleaned.
	Player contexts mirror automatically to that player's client.

	@within PlayerInputService
	@param actor InputActor
	@param contextName string
	@return callback
]=]
function PlayerInputService.PushActorContext(self: PlayerInputService, actor: InputActor, contextName: string): () -> ()
	return self:_getActorModel(actor):PushContext(contextName)
end

--[=[
	Pushes an authoritative player context until the returned callback is cleaned.

	@within PlayerInputService
	@param player Player
	@param contextName string
	@return callback
]=]
function PlayerInputService.PushPlayerContext(self: PlayerInputService, player: Player, contextName: string): () -> ()
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:PushActorContext(player, contextName)
end

--[=[
	Pushes an authoritative actor restriction until the returned callback is
	cleaned.

	@within PlayerInputService
	@param actor InputActor
	@param restriction RestrictionConfig
	@return callback
]=]
function PlayerInputService.PushActorRestriction(
	self: PlayerInputService,
	actor: InputActor,
	restriction: RestrictionConfig
): () -> ()
	return self:_getActorModel(actor):PushRestriction(restriction)
end

--[=[
	Pushes an authoritative player restriction until the returned callback is
	cleaned.

	@within PlayerInputService
	@param player Player
	@param restriction RestrictionConfig
	@return callback
]=]
function PlayerInputService.PushPlayerRestriction(
	self: PlayerInputService,
	player: Player,
	restriction: RestrictionConfig
): () -> ()
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:PushActorRestriction(player, restriction)
end

--[=[
	Cancels an actor's held action. Player cancellations also replicate to the
	client.

	@within PlayerInputService
	@param actor InputActor
	@param action Action
	@return boolean
]=]
function PlayerInputService.ForceReleaseActorInput(self: PlayerInputService, actor: InputActor, action: Action): boolean
	self:_assertRegisteredAction(action)
	const wasHeld = self:_getActorModel(actor):ForceRelease(action)

	if actor:IsA("Player") then
		PlayerInputServiceNetwork.packets.forceRelease.sendTo({
			actionId = action.Id,
		}, actor)
	end

	return wasHeld
end

--[=[
	Cancels a player's held action on both the server and client.

	@within PlayerInputService
	@param player Player
	@param action Action
	@return boolean
]=]
function PlayerInputService.ForceReleasePlayerInput(self: PlayerInputService, player: Player, action: Action): boolean
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:ForceReleaseActorInput(player, action)
end

--[=[
	Cancels every held action for an actor and returns the number released.
	Player cancellations also replicate to the client.

	@within PlayerInputService
	@param actor InputActor
	@return number
]=]
function PlayerInputService.ForceReleaseAllActorInputs(self: PlayerInputService, actor: InputActor): number
	const released = self:_getActorModel(actor):ForceReleaseAll()
	if actor:IsA("Player") then
		PlayerInputServiceNetwork.packets.forceReleaseAll.sendTo(nil, actor)
	end
	return released
end

--[=[
	Cancels every held action for a player on both the server and client and
	returns the number held authoritatively.

	@within PlayerInputService
	@param player Player
	@return number
]=]
function PlayerInputService.ForceReleaseAllPlayerInputs(self: PlayerInputService, player: Player): number
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:ForceReleaseAllActorInputs(player)
end

--[=[
	Sets an authoritative session binding override for one player.

	@within PlayerInputService
	@param player Player
	@param action Action
	@param inputModeType InputModeType
	@param inputTypes { InputType }
]=]
function PlayerInputService.SetPlayerBindingOverride(
	self: PlayerInputService,
	player: Player,
	action: Action,
	inputModeType: InputModeType.InputModeType,
	inputTypes: { InputType }
): ()
	assert(t.instanceIsA("Player")(player), "Bad player")
	const actorModel = self:_getActorModel(player)
	self:_assertRegisteredAction(action)
	assert(t.table(inputModeType) and InputModeType.isInputModeType(inputModeType), "Bad inputModeType")
	assert(t.table(inputTypes), "Bad inputTypes")
	assert(
		PlayerInputServiceUtils.findInputModeType(action, inputModeType.Name) == inputModeType,
		"Unknown inputModeType"
	)

	const serializedInputTypes = PlayerInputServiceUtils.serializeInputTypes(inputTypes)
	const bindingOverride, revision = actorModel:SetBindingOverride(action, inputModeType.Name, serializedInputTypes)

	PlayerInputServiceNetwork.packets.bindingOverrideChanged.sendTo({
		revision = revision,
		bindingOverride = bindingOverride,
	}, player)
end

--[=[
	Clears one authoritative session binding override.

	@within PlayerInputService
	@param player Player
	@param action Action
	@param inputModeType InputModeType
]=]
function PlayerInputService.ClearPlayerBindingOverride(
	self: PlayerInputService,
	player: Player,
	action: Action,
	inputModeType: InputModeType.InputModeType
): ()
	assert(t.instanceIsA("Player")(player), "Bad player")
	const actorModel = self:_getActorModel(player)
	self:_assertRegisteredAction(action)
	assert(t.table(inputModeType) and InputModeType.isInputModeType(inputModeType), "Bad inputModeType")
	assert(
		PlayerInputServiceUtils.findInputModeType(action, inputModeType.Name) == inputModeType,
		"Unknown inputModeType"
	)

	const bindingOverride, revision = actorModel:ClearBindingOverride(action, inputModeType.Name)
	if bindingOverride then
		PlayerInputServiceNetwork.packets.bindingOverrideChanged.sendTo({
			revision = revision,
			bindingOverride = bindingOverride,
		}, player)
	end
end

--[=[
	Clears every authoritative session binding override for one player.

	@within PlayerInputService
	@param player Player
]=]
function PlayerInputService.ClearPlayerBindingOverrides(self: PlayerInputService, player: Player): ()
	assert(t.instanceIsA("Player")(player), "Bad player")
	const actorModel = self:_getActorModel(player)

	for _, action in self._actionRegistryService:GetActions() do
		for _, inputKeyMap in action.InputKeyMapList:GetInputKeyMaps() do
			const bindingOverride, revision =
				actorModel:ClearBindingOverride(action, inputKeyMap:GetInputModeType().Name)
			if bindingOverride then
				PlayerInputServiceNetwork.packets.bindingOverrideChanged.sendTo({
					revision = revision,
					bindingOverride = bindingOverride,
				}, player)
			end
		end
	end
end

function PlayerInputService._getActorModel(
	self: PlayerInputService,
	actor: InputActor
): PlayerInputActorModel.PlayerInputActorModel
	assert(t.Instance(actor) and PlayerInputActorUtils.isInputActor(actor), "Bad actor")
	const actorRecord = self._actorRecords[actor]
	return if actorRecord then actorRecord.Model else error("Actor is not registered")
end

function PlayerInputService._assertRegisteredAction(self: PlayerInputService, action: Action): ()
	assert(t.table(action), "Bad action")
	assert(self._actionRegistryService:GetActionById(action.Id) == action, "Action is not registered")
end

function PlayerInputService._removeActorRecord(
	self: PlayerInputService,
	actor: InputActor,
	actorRecord: ActorRecord
): ()
	if self._actorRecords[actor] ~= actorRecord then
		return
	end

	self._actorRecords[actor] = nil
	self._maid[actorRecord.Maid] = nil
end

function PlayerInputService.Destroy(self: PlayerInputService): ()
	self._destroyed = true
	self._maid:DoCleaning()
	table.clear(self._actorRecords)
end

return PlayerInputService
