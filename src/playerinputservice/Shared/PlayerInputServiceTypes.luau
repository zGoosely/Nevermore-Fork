--!strict
--[=[
	Shared contracts for PlayerInputService actions, contexts, restrictions, and
	binding overrides.

	@types PlayerInputServiceTypes
]=]

const require = require("../../Loader").load()

const InputKeyMapList = require("InputKeyMapList")
const InputModeType = require("InputModeType")
const InputTypeUtils = require("InputTypeUtils")
const PlayerInputModeTypes = require("PlayerInputModeTypes")
const ServiceBag = require("ServiceBag")

export type InputActor = Player | Model
export type InputState = "Begin" | "End" | "Cancel"
export type ActionCooldownType = "Default" | "Burst"
export type ActionCooldownValue = {
	Duration: number,
	Count: number?,
	Window: number?,
	PenaltyDuration: number?,
}
export type InputResult =
	"Accepted"
	| "ActorNotRegistered"
	| "ActionNotRegistered"
	| "ActionNotServerEnabled"
	| "StateNotAllowed"
	| "ContextDenied"
	| "RestrictionDenied"
	| "InputModeDenied"
	| "ConditionFailed"
	| "RateLimited"
	| "AlreadyHeld"
	| "NotHeld"
export type NetworkInputState = "Begin" | "End"

export type NetworkPolicyConfig = {
	States: { NetworkInputState },
	Capacity: number,
	RefillRate: number,
}

export type NetworkPolicy = {
	States: { [NetworkInputState]: true },
	Capacity: number,
	RefillRate: number,
}

export type AdorneeConditionContext = (conditionContainer: BindableFunction) -> ()

export type ActionConfig = {
	Id: number,
	Name: string,
	InputKeyMapList: InputKeyMapList.InputKeyMapList,
	AllowedContexts: { string }?,
	AllowedPlayerInputModes: { PlayerInputModeTypes.PlayerInputModeType }?,
	ConsumeInput: boolean?,
	ContextActionPriority: number?,
	AllowWhenTextBoxFocused: boolean?,
	AdorneeConditionContext: AdorneeConditionContext?,
	ConsumeInputWhenConditionFails: boolean?,
	Network: NetworkPolicyConfig?,
	CooldownType: ActionCooldownType?,
	CooldownValue: ActionCooldownValue?,
	CooldownOnCancel: boolean?,
}

export type Action = {
	Id: number,
	Name: string,
	ProviderName: string,
	InputKeyMapList: InputKeyMapList.InputKeyMapList,
	AllowedContexts: { [string]: true },
	AllowedPlayerInputModes: { [PlayerInputModeTypes.PlayerInputModeType]: true },
	ConsumeInput: boolean,
	ContextActionPriority: number,
	AllowWhenTextBoxFocused: boolean,
	AdorneeConditionContext: BindableFunction?,
	ConsumeInputWhenConditionFails: boolean,
	Network: NetworkPolicy?,
	CooldownKey: string?,
	CooldownType: ActionCooldownType?,
	CooldownValue: ActionCooldownValue?,
	CooldownOnCancel: boolean,
}

export type Context = {
	Name: string,
	Priority: number,
}

export type RestrictionConfig = {
	Priority: number,
	Actions: { Action | number },
	Allowed: boolean,
}

export type Restriction = {
	Priority: number,
	Actions: { [number]: true },
	Allowed: boolean,
	Order: number,
}

export type SerializedInputType = {
	Kind: number,
	Name: string,
	Modifiers: { string }?,
}

export type BindingOverride = {
	ActionId: number,
	InputModeName: string,
	InputTypes: { SerializedInputType },
	Clear: boolean,
}

export type InitialState = {
	AllowedActionIds: { number },
	BindingOverrides: { BindingOverride },
	ContextName: string,
	PolicyRevision: number,
	BindingRevision: number,
}

export type ProviderLike = {
	GetProviderName: (self: ProviderLike) -> string,
	GetActions: (self: ProviderLike) -> { Action },
	GetContexts: (self: ProviderLike) -> { Context },
	ObserveInputKeyMapListsBrio: (self: ProviderLike) -> any,
	FindInputKeyMapList: (self: ProviderLike, name: string) -> InputKeyMapList.InputKeyMapList?,
}

export type ProviderBuilder = {
	AddAction: (self: ProviderBuilder, config: ActionConfig) -> Action,
	AddContext: (self: ProviderBuilder, name: string, priority: number) -> Context,
}

export type CreateDefaultsCallback = (provider: ProviderBuilder, serviceBag: ServiceBag.ServiceBag) -> ()

export type InputMode = InputModeType.InputModeType
export type InputType = InputTypeUtils.InputType

return {}
