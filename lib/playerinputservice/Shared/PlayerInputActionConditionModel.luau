--!strict
--[=[
	Tracks whether one action's adornee conditions currently permit a player
	character or NPC actor.

	@class PlayerInputActionConditionModel
]=]

const require = require("../../Loader").load()

const AdorneeConditionUtils = require("AdorneeConditionUtils")
const Maid = require("Maid")
const PlayerInputActorUtils = require("PlayerInputActorUtils")
const PlayerInputServiceTypes = require("PlayerInputServiceTypes")
const Rx = require("Rx")
const RxCharacterUtils = require("RxCharacterUtils")
const t = require("t")

type Action = PlayerInputServiceTypes.Action
type InputActor = PlayerInputServiceTypes.InputActor

const PlayerInputActionConditionModel = {}
PlayerInputActionConditionModel.ClassName = "PlayerInputActionConditionModel"
PlayerInputActionConditionModel.__index = PlayerInputActionConditionModel

export type PlayerInputActionConditionModel = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_conditionsMet: boolean,
	},
	{} :: typeof({ __index = PlayerInputActionConditionModel })
))

function PlayerInputActionConditionModel.new(actor: InputActor, action: Action): PlayerInputActionConditionModel
	assert(t.Instance(actor) and PlayerInputActorUtils.isInputActor(actor), "Bad actor")
	assert(t.table(action), "Bad action")

	const self = setmetatable({}, PlayerInputActionConditionModel) :: PlayerInputActionConditionModel
	self._maid = Maid.new()
	self._conditionsMet = action.AdorneeConditionContext == nil

	const conditionContext = action.AdorneeConditionContext
	if conditionContext then
		const observeAdornee = if actor:IsA("Player")
			then RxCharacterUtils.observeCharacter(actor)
			else Rx.of(actor :: Model)

		self._maid:Add(observeAdornee
			:Pipe({
				Rx.switchMap(function(character: Model?): any
					if not character then
						return Rx.of(false)
					end

					return AdorneeConditionUtils.observeConditionsMet(conditionContext, character):Pipe({
						Rx.map(function(conditionsMet)
							return conditionsMet == true
						end),
					})
				end) :: any,
				Rx.distinct() :: any,
			})
			:Subscribe(function(conditionsMet)
				self._conditionsMet = conditionsMet
			end, function(reason)
				self._conditionsMet = false
				warn(
					`[PlayerInputActionConditionModel] Failed to evaluate {action.ProviderName}.{action.Name}: {tostring(
						reason
					)}`
				)
			end))
	end

	return self
end

--[=[
	Returns whether the latest character condition state permits this action.

	@within PlayerInputActionConditionModel
	@return boolean
]=]
function PlayerInputActionConditionModel.AreConditionsMet(self: PlayerInputActionConditionModel): boolean
	return self._conditionsMet
end

function PlayerInputActionConditionModel.Destroy(self: PlayerInputActionConditionModel): ()
	self._maid:DoCleaning()
end

return PlayerInputActionConditionModel
