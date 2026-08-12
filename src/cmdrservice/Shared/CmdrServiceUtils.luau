--!strict
--[=[
	Shared types and context helpers for [CmdrService].

	@util CmdrServiceUtils
]=]

const require = require("../../Loader").load()

const ServiceBag = require("ServiceBag")

const CmdrServiceUtils = {}

export type CommandArgument = {
	Type: any,
	Name: string,
	Description: string?,
	Optional: boolean?,
	Default: any?,
}

export type CommandExecute = (context: any, ...any) -> ...any

export type CommandDefinition = {
	Name: string,
	Description: string?,
	Group: string?,
	Aliases: { string }?,
	AutoExec: { string }?,
	Args: { CommandArgument }?,
	Run: CommandExecute?,
}

--[=[
	Gets the ServiceBag from a Cmdr context or registry.

	@within CmdrServiceUtils
	@param context any
	@return ServiceBag
]=]
function CmdrServiceUtils.getServiceBag(context: any): ServiceBag.ServiceBag
	return context:GetStore("ServiceBag").ServiceBag
end

--[=[
	Writes the ServiceBag into a Cmdr context or registry.

	@within CmdrServiceUtils
	@param context any
	@param serviceBag ServiceBag
]=]
function CmdrServiceUtils.writeServiceBagInContext(context: any, serviceBag: ServiceBag.ServiceBag)
	const store = context:GetStore("ServiceBag")
	store.ServiceBag = serviceBag
end

return CmdrServiceUtils
