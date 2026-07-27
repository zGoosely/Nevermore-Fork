--!strict
--[=[
	Canonical results returned by authoritative actor input attempts.

	@class PlayerInputResults
]=]

const require = require("../../Loader").load()

const Enums = require("Enums")

return Enums.new({
	Accepted = "Accepted" :: "Accepted",
	ActorNotRegistered = "ActorNotRegistered" :: "ActorNotRegistered",
	ActionNotRegistered = "ActionNotRegistered" :: "ActionNotRegistered",
	ActionNotServerEnabled = "ActionNotServerEnabled" :: "ActionNotServerEnabled",
	StateNotAllowed = "StateNotAllowed" :: "StateNotAllowed",
	ContextDenied = "ContextDenied" :: "ContextDenied",
	RestrictionDenied = "RestrictionDenied" :: "RestrictionDenied",
	InputModeDenied = "InputModeDenied" :: "InputModeDenied",
	ConditionFailed = "ConditionFailed" :: "ConditionFailed",
	RateLimited = "RateLimited" :: "RateLimited",
	AlreadyHeld = "AlreadyHeld" :: "AlreadyHeld",
	NotHeld = "NotHeld" :: "NotHeld",
})
