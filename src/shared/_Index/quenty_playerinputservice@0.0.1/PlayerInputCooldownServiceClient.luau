--!strict
--[=[
	Automatically maps configured replicated or predicted cooldown state onto
	local PlayerInputServiceClient restrictions.

	@class PlayerInputCooldownServiceClient
	@client
]=]

const Players = game:GetService("Players")
const CooldownServiceClient = require("@game/ReplicatedStorage/Packages/CooldownServiceClient")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const PlayerInputActionRegistryServiceShared = require("./Shared/PlayerInputActionRegistryServiceShared")
const PlayerInputCooldownServiceConstants = require("./Shared/PlayerInputCooldownServiceConstants")
const PlayerInputCooldownServiceTypes = require("./Shared/PlayerInputCooldownServiceTypes")
const PlayerInputCooldownServiceUtils = require("./Shared/PlayerInputCooldownServiceUtils")
const PlayerInputServiceClient = require("./PlayerInputServiceClient")
const PlayerInputServiceTypes = require("./Shared/PlayerInputServiceTypes")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

type Action = PlayerInputServiceTypes.Action
type ActionBindingConfig = PlayerInputCooldownServiceTypes.ClientActionBindingConfig
type BindingConfig = PlayerInputCooldownServiceTypes.ClientBindingConfig

const PlayerInputCooldownServiceClient = {}
PlayerInputCooldownServiceClient.ServiceName = "PlayerInputCooldownServiceClient"

export type PlayerInputCooldownServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_actionRegistryService: PlayerInputActionRegistryServiceShared.PlayerInputActionRegistryServiceShared,
		_cooldownServiceClient: CooldownServiceClient.CooldownServiceClient,
		_playerInputServiceClient: PlayerInputServiceClient.PlayerInputServiceClient,
	},
	{} :: typeof({ __index = PlayerInputCooldownServiceClient })
))

function PlayerInputCooldownServiceClient.Init(
	self: PlayerInputCooldownServiceClient,
	serviceBag: ServiceBag.ServiceBag
): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._actionRegistryService = self._serviceBag:GetService(PlayerInputActionRegistryServiceShared)
	self._cooldownServiceClient = self._serviceBag:GetService(CooldownServiceClient)
	self._playerInputServiceClient = self._serviceBag:GetService(PlayerInputServiceClient)
end

function PlayerInputCooldownServiceClient.Start(self: PlayerInputCooldownServiceClient): ()
	self._maid:Add(self._actionRegistryService:ObserveActionsBrio():Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		const actionMaid, action = brio:ToMaidAndValue()
		if PlayerInputCooldownServiceUtils.isActionCooldownConfigured(action) then
			actionMaid:Add(self:BindAction({
				Owner = Players.LocalPlayer,
				Action = action,
			}))
		end
	end))
end

--[=[
	Denies mapped local actions while an effective cooldown is active. Predictions
	therefore suppress input before authoritative state replicates.

	@within PlayerInputCooldownServiceClient
	@param config ClientBindingConfig
	@return () -> ()
]=]
function PlayerInputCooldownServiceClient.Bind(self: PlayerInputCooldownServiceClient, config: BindingConfig): () -> ()
	assert(PlayerInputCooldownServiceUtils.isClientBindingConfig(config), "Bad config")

	const priority = config.Priority or PlayerInputCooldownServiceConstants.DEFAULT_RESTRICTION_PRIORITY
	const bindingMaid = Maid.new()
	self._maid[bindingMaid] = bindingMaid
	bindingMaid:Add(
		self._cooldownServiceClient:ObserveIsOnCooldown(config.Owner, config.Key):Subscribe(function(isOnCooldown)
			bindingMaid._restriction = nil
			if isOnCooldown then
				bindingMaid._restriction = self._playerInputServiceClient:PushRestriction({
					Priority = priority,
					Actions = config.Actions,
					Allowed = false,
				})
			end
		end)
	)

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
	Binds the cooldown declared directly by one local action.

	@within PlayerInputCooldownServiceClient
	@param config ClientActionBindingConfig
	@return () -> ()
]=]
function PlayerInputCooldownServiceClient.BindAction(
	self: PlayerInputCooldownServiceClient,
	config: ActionBindingConfig
): () -> ()
	assert(PlayerInputCooldownServiceUtils.isClientActionBindingConfig(config), "Bad config")

	const key = PlayerInputCooldownServiceUtils.getActionCooldownDefinition(config.Action)
	return self:Bind({
		Owner = config.Owner,
		Key = key,
		Actions = { config.Action },
		Priority = config.Priority,
	})
end

--[=[
	Returns whether an action's authoritative or predicted move cooldown is
	active for an owner.

	@within PlayerInputCooldownServiceClient
	@param owner Instance
	@param action Action
	@return boolean
]=]
function PlayerInputCooldownServiceClient.IsActionOnCooldown(
	self: PlayerInputCooldownServiceClient,
	owner: Instance,
	action: Action
): boolean
	assert(t.Instance(owner), "Bad owner")
	const key = PlayerInputCooldownServiceUtils.getActionCooldownDefinition(action)
	return self._cooldownServiceClient:IsOnCooldown(owner, key)
end

--[=[
	Predicts an action's move-specific base cooldown and returns an idempotent
	cancellation callback.

	@within PlayerInputCooldownServiceClient
	@param owner Instance
	@param action Action
	@return () -> ()
]=]
function PlayerInputCooldownServiceClient.PredictActionCooldown(
	self: PlayerInputCooldownServiceClient,
	owner: Instance,
	action: Action
): () -> ()
	assert(t.Instance(owner), "Bad owner")
	const key, cooldownType, cooldownValue = PlayerInputCooldownServiceUtils.getActionCooldownDefinition(action)
	return self._cooldownServiceClient:PredictTypedCooldown(owner, key, cooldownType, cooldownValue)
end

function PlayerInputCooldownServiceClient.Destroy(self: PlayerInputCooldownServiceClient): ()
	self._maid:DoCleaning()
end

return PlayerInputCooldownServiceClient
