--!strict
--[=[
	@class PermissionLevel
]=]
local Enums = require("@game/ReplicatedStorage/Packages/Enums")

export type PermissionLevelType = "admin" | "creator"

return Enums.new({
	ADMIN = "admin" :: "admin",
	CREATOR = "creator" :: "creator",
})
