--!strict
--[=[
	Shared contracts for cooldown state, clocks, and expiry scheduling.

	@types CooldownServiceTypes
]=]
const Signal = require("@game/ReplicatedStorage/Packages/Signal")

export type Clock = () -> number

export type CooldownType = "Default" | "Burst"

export type DefaultCooldownValue = {
	Duration: number,
}

export type BurstCooldownValue = {
	Duration: number,
	Count: number,
	Window: number,
	PenaltyDuration: number,
}

export type CooldownValue = DefaultCooldownValue | BurstCooldownValue

export type CooldownState = {
	Owner: Instance,
	Key: string,
	StartedAt: number,
	EndsAt: number,
	IsPredicted: boolean,
}

export type CooldownModel = {
	Changed: Signal.Signal<()>,
	GetFolder: (self: CooldownModel) -> Folder,
	GetState: (self: CooldownModel) -> CooldownState?,
	GetOwner: (self: CooldownModel) -> Instance?,
	GetKey: (self: CooldownModel) -> string,
	GetStartedAt: (self: CooldownModel) -> number,
	GetEndsAt: (self: CooldownModel) -> number,
	GetDuration: (self: CooldownModel) -> number,
	GetRemainingTime: (self: CooldownModel) -> number,
	IsActive: (self: CooldownModel) -> boolean,
	IsPredicted: (self: CooldownModel) -> boolean,
	Destroy: (self: CooldownModel) -> (),
}

export type HeapEntry<T> = {
	Priority: number,
	Value: T,
	Version: number,
}

return {}
