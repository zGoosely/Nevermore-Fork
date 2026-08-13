--!strict
--[=[
	Canonical cooldown policy types.

	@class CooldownTypes
]=]
const Enums = require("@game/ReplicatedStorage/Packages/Enums")

export type CooldownType = "Default" | "Burst"

return Enums.new({
	Default = "Default" :: "Default",
	Burst = "Burst" :: "Burst",
})
