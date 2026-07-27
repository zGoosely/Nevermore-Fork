--!strict
--[=[
	Replication modes used by [TemplateProvider].

	@class TemplateReplicationModes
]=]

export type TemplateReplicationMode = "client" | "server" | "shared"

return table.freeze({
	CLIENT = "client" :: "client",
	SERVER = "server" :: "server",
	SHARED = "shared" :: "shared",
})
