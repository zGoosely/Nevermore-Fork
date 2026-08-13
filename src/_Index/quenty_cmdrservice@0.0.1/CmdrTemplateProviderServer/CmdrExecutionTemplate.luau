--!strict
--[=[
	Forwards a generated Cmdr command to the function retained by its server-side
	[CmdrService].

	@class CmdrExecutionTemplate
]=]

const cmdrServiceId = (script:WaitForChild("CmdrServiceId") :: StringValue).Value
const cmdrCommandId = (script:WaitForChild("CmdrCommandId") :: StringValue).Value
const cmdrServiceTarget = (script:WaitForChild("CmdrServiceTarget") :: ObjectValue).Value

assert(cmdrServiceId ~= "", "No CmdrServiceId")
assert(cmdrCommandId ~= "", "No CmdrCommandId")
assert(cmdrServiceTarget and cmdrServiceTarget:IsA("ModuleScript"), "No CmdrServiceTarget")

const cmdrServiceDefinition = require(cmdrServiceTarget)
const cmdrService = assert(cmdrServiceDefinition:__getServiceFromId(cmdrServiceId), "CmdrService is unavailable")

return function(...: any): ...any
	return cmdrService:__executeCommand(cmdrCommandId, ...)
end
