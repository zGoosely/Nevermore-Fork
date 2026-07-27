--!strict
--[=[
	Provides the ModuleScript templates used to register table-defined Cmdr
	commands.

	@server
	@class CmdrTemplateProviderServer
]=]

const require = require("../Loader").load()

const TemplateProvider = require("TemplateProvider")

return TemplateProvider.new(script.Name, script)
