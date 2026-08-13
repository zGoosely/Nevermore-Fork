--!strict
--[=[
	@class InputKeyMapService
]=]
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local InputKeyMapService = {}
InputKeyMapService.ServiceName = "InputKeyMapService"

export type InputKeyMapService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
	},
	{} :: typeof({ __index = InputKeyMapService })
))

function InputKeyMapService.Init(self: InputKeyMapService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	-- Internal
	self._serviceBag:GetService(require("./Shared/InputKeyMapRegistryServiceShared"))
	self._serviceBag:GetService(require("./Shared/InputKeyMapTranslator"))
end

return InputKeyMapService
