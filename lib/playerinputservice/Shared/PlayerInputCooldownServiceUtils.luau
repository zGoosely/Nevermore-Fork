--!strict
--[=[
	Validates configuration for the optional PlayerInput cooldown services.

	@util PlayerInputCooldownServiceUtils
]=]

const require = require("../../Loader").load()

const ActionExecutionStatuses = require("ActionExecutionStatuses")
const ActionExecutionTypes = require("ActionExecutionTypes")
const ActionExecutionUtils = require("ActionExecutionUtils")
const CooldownServiceTypes = require("CooldownServiceTypes")
const CooldownServiceUtils = require("CooldownServiceUtils")
const CooldownTypes = require("CooldownTypes")
const PlayerInputActorUtils = require("PlayerInputActorUtils")
const PlayerInputCooldownServiceTypes = require("PlayerInputCooldownServiceTypes")
const PlayerInputServiceTypes = require("PlayerInputServiceTypes")
const t = require("t")

type Action = PlayerInputServiceTypes.Action
type ActionExecutionStatus = ActionExecutionTypes.Status
type ClientBindingConfig = PlayerInputCooldownServiceTypes.ClientBindingConfig
type CooldownType = CooldownServiceTypes.CooldownType
type CooldownValue = CooldownServiceTypes.CooldownValue
type LegacyServerPlayerBindingConfig = PlayerInputCooldownServiceTypes.LegacyServerPlayerBindingConfig
type ServerActorBindingConfig = PlayerInputCooldownServiceTypes.ServerActorBindingConfig
type ServerBindingConfig = PlayerInputCooldownServiceTypes.ServerBindingConfig
type InputActor = PlayerInputServiceTypes.InputActor

const isServerActorBindingShape = t.strictInterface({
	Actor = t.Instance,
	Owner = t.Instance,
	Key = t.string,
	Actions = t.array(t.table),
	Priority = t.optional(t.number),
})

const isLegacyServerPlayerBindingShape = t.strictInterface({
	Player = t.instanceIsA("Player"),
	Owner = t.Instance,
	Key = t.string,
	Actions = t.array(t.table),
	Priority = t.optional(t.number),
})

const isClientBindingShape = t.strictInterface({
	Owner = t.Instance,
	Key = t.string,
	Actions = t.array(t.table),
	Priority = t.optional(t.number),
})

const isServerActionBindingShape = t.strictInterface({
	Actor = t.Instance,
	Owner = t.Instance,
	Action = t.table,
	Priority = t.optional(t.number),
})

const isClientActionBindingShape = t.strictInterface({
	Owner = t.Instance,
	Action = t.table,
	Priority = t.optional(t.number),
})

const PlayerInputCooldownServiceUtils = {}

local function isActionList(actions: { any }): boolean
	if #actions == 0 then
		return false
	end

	for _, action in actions do
		if not t.number(action.Id) then
			return false
		end
	end

	return true
end

--[=[
	Returns whether an action owns a valid move-specific cooldown definition.

	@within PlayerInputCooldownServiceUtils
	@param action Action
	@return boolean
]=]
function PlayerInputCooldownServiceUtils.isActionCooldownConfigured(action: any): boolean
	if
		not t.table(action)
		or not CooldownServiceUtils.isCooldownKey(action.CooldownKey)
		or not t.string(action.CooldownType)
		or not CooldownTypes:IsValue(action.CooldownType)
	then
		return false
	end

	if action.CooldownType == CooldownTypes.Default then
		return CooldownServiceUtils.isDefaultCooldownValue(action.CooldownValue)
	end

	return CooldownServiceUtils.isBurstCooldownValue(action.CooldownValue)
end

--[=[
	Returns a validated action's move-specific cooldown definition.

	@within PlayerInputCooldownServiceUtils
	@param action Action
	@return string, CooldownType, CooldownValue
]=]
function PlayerInputCooldownServiceUtils.getActionCooldownDefinition(
	action: Action
): (string, CooldownType, CooldownValue)
	assert(PlayerInputCooldownServiceUtils.isActionCooldownConfigured(action), "Action has no valid cooldown")

	return action.CooldownKey :: string, action.CooldownType :: CooldownType, action.CooldownValue :: CooldownValue
end

--[=[
	Returns whether an authoritative execution result should activate its
	action's cooldown.

	@within PlayerInputCooldownServiceUtils
	@param action Action
	@param status ActionExecutionStatus
	@return boolean
]=]
function PlayerInputCooldownServiceUtils.shouldStartActionCooldown(
	action: Action,
	status: ActionExecutionStatus
): boolean
	assert(t.table(action), "Bad action")
	assert(t.string(status) and ActionExecutionUtils.isStatus(status), "Bad status")

	return status == ActionExecutionStatuses.SUCCEEDED
		or (status == ActionExecutionStatuses.CANCELLED and action.CooldownOnCancel)
end

--[=[
	Returns whether a value is a valid server binding configuration.

	@within PlayerInputCooldownServiceUtils
	@param value any
	@return boolean
]=]
function PlayerInputCooldownServiceUtils.isServerBindingConfig(value: any): boolean
	const hasValidShape = (isServerActorBindingShape(value) and PlayerInputActorUtils.isInputActor(value.Actor))
		or isLegacyServerPlayerBindingShape(value)

	return hasValidShape
		and CooldownServiceUtils.isCooldownKey(value.Key)
		and isActionList(value.Actions)
		and (value.Priority == nil or CooldownServiceUtils.isFiniteNumber(value.Priority))
end

--[=[
	Returns the actor targeted by a validated server binding.

	@within PlayerInputCooldownServiceUtils
	@param config ServerBindingConfig
	@return InputActor
]=]
function PlayerInputCooldownServiceUtils.getServerBindingActor(config: ServerBindingConfig): InputActor
	assert(PlayerInputCooldownServiceUtils.isServerBindingConfig(config), "Bad config")

	const actor = (config :: ServerActorBindingConfig).Actor
	if actor then
		return actor
	end

	return (config :: LegacyServerPlayerBindingConfig).Player
end

--[=[
	Returns whether a value can bind one move-specific actor cooldown.

	@within PlayerInputCooldownServiceUtils
	@param value any
	@return boolean
]=]
function PlayerInputCooldownServiceUtils.isServerActionBindingConfig(value: any): boolean
	return isServerActionBindingShape(value)
		and PlayerInputActorUtils.isInputActor(value.Actor)
		and PlayerInputCooldownServiceUtils.isActionCooldownConfigured(value.Action)
		and (value.Priority == nil or CooldownServiceUtils.isFiniteNumber(value.Priority))
end

--[=[
	Returns whether a value is a valid client binding configuration.

	@within PlayerInputCooldownServiceUtils
	@param value any
	@return boolean
]=]
function PlayerInputCooldownServiceUtils.isClientBindingConfig(value: any): boolean
	return isClientBindingShape(value)
		and CooldownServiceUtils.isCooldownKey(value.Key)
		and isActionList(value.Actions)
		and (value.Priority == nil or CooldownServiceUtils.isFiniteNumber(value.Priority))
end

--[=[
	Returns whether a value can bind one local move-specific cooldown.

	@within PlayerInputCooldownServiceUtils
	@param value any
	@return boolean
]=]
function PlayerInputCooldownServiceUtils.isClientActionBindingConfig(value: any): boolean
	return isClientActionBindingShape(value)
		and PlayerInputCooldownServiceUtils.isActionCooldownConfigured(value.Action)
		and (value.Priority == nil or CooldownServiceUtils.isFiniteNumber(value.Priority))
end

return PlayerInputCooldownServiceUtils
