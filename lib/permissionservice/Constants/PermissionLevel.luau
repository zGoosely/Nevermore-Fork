--!strict
--[=[
	@class PermissionLevel
]=]

const require = require("../../Loader").load()

local Enums = require("Enums")

export type PermissionLevelType = "admin" | "creator"

return Enums.new({
	ADMIN = "admin" :: "admin",
	CREATOR = "creator" :: "creator",
})
