--!strict
--[=[
	Automatically maps authoritative action cooldowns onto PlayerInputService
	restrictions and starts them from completed action executions.

	@class PlayerInputCooldownService
	@server
]=]
const ActionExecution = require("@game/ReplicatedStorage/Packages/ActionExecution")
const ActionExecutionService = require("@game/ReplicatedStorage/Packages/ActionExecutionService")
const ActionExecutionTypes = require("@game/ReplicatedStorage/Packages/ActionExecutionTypes")
const ActionExecutionUtils = require("@game/ReplicatedStorage/Packages/ActionExecutionUtils")
const Cooldown = require("@game/ReplicatedStorage/Packages/Cooldown")
const CooldownService = require("@game/ReplicatedStorage/Packages/CooldownService")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const PlayerInputActionRegistryServiceShared = require("./Shared/PlayerInputActionRegistryServiceShared")
const PlayerInputCooldownServiceConstants = require("./Shared/PlayerInputCooldownServiceConstants")
const PlayerInputCooldownServiceTypes = require("./Shared/PlayerInputCooldownServiceTypes")
const PlayerInputCooldownServiceUtils = require("./Shared/PlayerInputCooldownServiceUtils")
const PlayerInputService = require("./PlayerInputService")
const PlayerInputServiceTypes = require("./Shared/PlayerInputServiceTypes")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

type BindingConfig = PlayerInputCooldownServiceTypes.ServerBindingConfig
type Action = PlayerInputServiceTypes.Action
type ActionBindingConfig = PlayerInputCooldownServiceTypes.ServerActionBindingConfig
type ExecutionCallback = ActionExecutionTypes.ExecutionCallback
type ExecutionConfig = ActionExecutionTypes.ExecutionConfig

const PlayerInputCooldownService = {}
PlayerInputCooldownService.ServiceName = "PlayerInputCooldownService"
PlayerInputCooldownService.ServerOnly = true

export type PlayerInputCooldownService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_actionExecutionService: ActionExecutionService.ActionExecutionService,
		_actionRegistryService: PlayerInputActionRegistryServiceShared.PlayerInputActionRegistryServiceShared,
		_cooldownService: CooldownService.CooldownService,
		_playerInputService: PlayerInputService.PlayerInputService,
	},
	{} :: typeof({ __index = PlayerInputCooldownService })
))

function PlayerInputCooldownService.Init(self: PlayerInputCooldownService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._actionExecutionService = self._serviceBag:GetService(ActionExecutionService)
	self._actionRegistryService = self._serviceBag:GetService(PlayerInputActionRegistryServiceShared)
	self._cooldownService = self._serviceBag:GetService(CooldownService)
	self._playerInputService = self._serviceBag:GetService(PlayerInputService)
end

function PlayerInputCooldownService.Start(self: PlayerInputCooldownService): ()
	self._maid:Add(self._playerInputService:ObserveActorsBrio():Subscribe(function(actorBrio)
		if actorBrio:IsDead() then
			return
		end

		const actorMaid, actor = actorBrio:ToMaidAndValue()
		actorMaid:Add(self._actionRegistryService:ObserveActionsBrio():Subscribe(function(actionBrio)
			if actionBrio:IsDead() then
				return
			end

			const actionMaid, action = actionBrio:ToMaidAndValue()
			if PlayerInputCooldownServiceUtils.isActionCooldownConfigured(action) then
				actionMaid:Add(self:BindAction({
					Actor = actor,
					Owner = actor,
					Action = action,
				}))
			end
		end))
	end))
end

--[=[
	Denies mapped actions while an authoritative cooldown is active. The returned
	callback removes both the observation and any current restriction.

	@within PlayerInputCooldownService
	@param config ServerBindingConfig
	@return () -> ()
]=]
function PlayerInputCooldownService.Bind(self: PlayerInputCooldownService, config: BindingConfig): () -> ()
	assert(PlayerInputCooldownServiceUtils.isServerBindingConfig(config), "Bad config")

	const actor = PlayerInputCooldownServiceUtils.getServerBindingActor(config)
	const priority = config.Priority or PlayerInputCooldownServiceConstants.DEFAULT_RESTRICTION_PRIORITY
	const bindingMaid = Maid.new()
	self._maid[bindingMaid] = bindingMaid
	bindingMaid:Add(self._cooldownService:ObserveIsOnCooldown(config.Owner, config.Key):Subscribe(function(isOnCooldown)
		bindingMaid._restriction = nil
		if isOnCooldown then
			bindingMaid._restriction = self._playerInputService:PushActorRestriction(actor, {
				Priority = priority,
				Actions = config.Actions,
				Allowed = false,
			})
		end
	end))

	local isDestroyed = false
	return function()
		if isDestroyed then
			return
		end
		isDestroyed = true
		self._maid[bindingMaid] = nil
	end
end

--[=[
	Binds the cooldown declared directly by one action.

	@within PlayerInputCooldownService
	@param config ServerActionBindingConfig
	@return () -> ()
]=]
function PlayerInputCooldownService.BindAction(self: PlayerInputCooldownService, config: ActionBindingConfig): () -> ()
	assert(PlayerInputCooldownServiceUtils.isServerActionBindingConfig(config), "Bad config")

	const key = PlayerInputCooldownServiceUtils.getActionCooldownDefinition(config.Action)
	return self:Bind({
		Actor = config.Actor,
		Owner = config.Owner,
		Key = key,
		Actions = { config.Action },
		Priority = config.Priority,
	})
end

--[=[
	Starts authoritative cancellable work for a configured action when its
	cooldown and optional execution lock are ready. Success starts the cooldown;
	cancellation also starts it when `CooldownOnCancel` is enabled.

	@within PlayerInputCooldownService
	@param action Action
	@param config ExecutionConfig
	@param callback ExecutionCallback
	@return ActionExecution?
]=]
function PlayerInputCooldownService.TryStartActionExecution(
	self: PlayerInputCooldownService,
	action: Action,
	config: ExecutionConfig,
	callback: ExecutionCallback
): ActionExecution.ActionExecution?
	assert(PlayerInputCooldownServiceUtils.isActionCooldownConfigured(action), "Action has no valid cooldown")
	assert(self._actionRegistryService:GetActionById(action.Id) == action, "Action is not registered")
	assert(ActionExecutionUtils.isExecutionConfig(config), "Bad config")
	assert(t.callback(callback), "Bad callback")

	if self:IsActionOnCooldown(config.Actor, action) then
		return nil
	end

	const execution = self._actionExecutionService:TryStart(config, callback)
	if not execution then
		return nil
	end

	self:_trackActionExecutionCooldown(action, execution)
	return execution
end

--[=[
	Returns whether an action's move-specific cooldown is active for an owner.

	@within PlayerInputCooldownService
	@param owner Instance
	@param action Action
	@return boolean
]=]
function PlayerInputCooldownService.IsActionOnCooldown(
	self: PlayerInputCooldownService,
	owner: Instance,
	action: Action
): boolean
	assert(t.Instance(owner), "Bad owner")
	const key = PlayerInputCooldownServiceUtils.getActionCooldownDefinition(action)
	return self._cooldownService:IsOnCooldown(owner, key)
end

--[=[
	Starts an action's move-specific cooldown after successful game logic.

	@within PlayerInputCooldownService
	@param owner Instance
	@param action Action
	@return Cooldown?
]=]
function PlayerInputCooldownService.StartActionCooldown(
	self: PlayerInputCooldownService,
	owner: Instance,
	action: Action
): Cooldown.Cooldown?
	assert(t.Instance(owner), "Bad owner")
	const key, cooldownType, cooldownValue = PlayerInputCooldownServiceUtils.getActionCooldownDefinition(action)
	return self._cooldownService:StartTypedCooldown(owner, key, cooldownType, cooldownValue)
end

function PlayerInputCooldownService._trackActionExecutionCooldown(
	self: PlayerInputCooldownService,
	action: Action,
	execution: ActionExecution.ActionExecution
): ()
	self._maid[execution] = execution:ObserveStatus():Subscribe(function(status)
		if not ActionExecutionUtils.isTerminalStatus(status) then
			return
		end

		if PlayerInputCooldownServiceUtils.shouldStartActionCooldown(action, status) then
			self:StartActionCooldown(execution:GetActor(), action)
		end
		self._maid[execution] = nil
	end)
end

function PlayerInputCooldownService.Destroy(self: PlayerInputCooldownService): ()
	self._maid:DoCleaning()
end

return PlayerInputCooldownService
