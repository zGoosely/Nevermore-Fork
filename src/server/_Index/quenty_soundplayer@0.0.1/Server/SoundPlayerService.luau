--!strict
--[=[
    @class SoundPlayerService
]=]
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local SoundPlayerService = {}
SoundPlayerService.ServiceName = "SoundPlayerService"

export type SoundPlayerService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
	},
	{} :: typeof({ __index = SoundPlayerService })
))

function SoundPlayerService.Init(self: SoundPlayerService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	self._serviceBag:GetService(require("@game/ServerStorage/ServerPackages/SoundGroupService"))
end

return SoundPlayerService
