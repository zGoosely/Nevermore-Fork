--!strict
--[=[
	Configuration contracts for the optional PlayerInput cooldown services.

	@types PlayerInputCooldownServiceTypes
]=]

const require = require("../../Loader").load()

const PlayerInputServiceTypes = require("PlayerInputServiceTypes")

type Action = PlayerInputServiceTypes.Action
type InputActor = PlayerInputServiceTypes.InputActor

export type ServerActorBindingConfig = {
	Actor: InputActor,
	Owner: Instance,
	Key: string,
	Actions: { Action },
	Priority: number?,
}

export type LegacyServerPlayerBindingConfig = {
	Player: Player,
	Owner: Instance,
	Key: string,
	Actions: { Action },
	Priority: number?,
}

export type ServerBindingConfig = ServerActorBindingConfig | LegacyServerPlayerBindingConfig

export type ServerActionBindingConfig = {
	Actor: InputActor,
	Owner: Instance,
	Action: Action,
	Priority: number?,
}

export type ClientBindingConfig = {
	Owner: Instance,
	Key: string,
	Actions: { Action },
	Priority: number?,
}

export type ClientActionBindingConfig = {
	Owner: Instance,
	Action: Action,
	Priority: number?,
}

return {}
