--!strict
--[=[
	Decodes a generated Cmdr command definition.

	@class CmdrCommandDefinitionTemplate
]=]

const HttpService = game:GetService("HttpService")

const commandDataValue = script:WaitForChild("CmdrJsonCommandData") :: StringValue

return HttpService:JSONDecode(commandDataValue.Value)
