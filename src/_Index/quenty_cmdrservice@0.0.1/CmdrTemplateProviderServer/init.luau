--!strict
--[=[
	Provides the ModuleScript templates used to register table-defined Cmdr
	commands.

	@server
	@class CmdrTemplateProviderServer
]=]
const TemplateProvider = require("@game/ReplicatedStorage/Packages/TemplateProvider")

return TemplateProvider.new(script.Name, script)
