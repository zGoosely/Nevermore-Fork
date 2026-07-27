--!strict
--[=[
	Canonical cooldown policy types.

	@class CooldownTypes
]=]

const require = require("../../Loader").load()

const Enums = require("Enums")

export type CooldownType = "Default" | "Burst"

return Enums.new({
	Default = "Default" :: "Default",
	Burst = "Burst" :: "Burst",
})
