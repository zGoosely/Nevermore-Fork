--!strict
--[=[
	Realms sort of have to be a first class citizen...

	@class TieRealms
]=]

local require = require("../../../Loader").load()

local SimpleEnum = require("Enums")

export type TieRealm = "shared" | "client" | "server"

return SimpleEnum.new({
	SHARED = "shared" :: "shared",
	CLIENT = "client" :: "client",
	SERVER = "server" :: "server",
})
