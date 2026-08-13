--!strict
--[=[
	Realms sort of have to be a first class citizen...

	@class TieRealms
]=]
local SimpleEnum = require("@game/ReplicatedStorage/Packages/Enums")

export type TieRealm = "shared" | "client" | "server"

return SimpleEnum.new({
	SHARED = "shared" :: "shared",
	CLIENT = "client" :: "client",
	SERVER = "server" :: "server",
})
