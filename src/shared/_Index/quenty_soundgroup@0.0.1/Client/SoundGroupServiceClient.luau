--!strict
--[=[
	@class SoundGroupServiceClient
]=]
local Maid = require("@game/ReplicatedStorage/Packages/Maid")
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local SoundGroupServiceClient = {}
SoundGroupServiceClient.ServiceName = "SoundGroupServiceClient"

export type SoundGroupServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
	},
	{} :: typeof({ __index = SoundGroupServiceClient })
))

function SoundGroupServiceClient.Init(self: SoundGroupServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	-- External
	self._serviceBag:GetService(require("@game/ReplicatedStorage/Packages/TieRealmService"))
	self._serviceBag:GetService(require("@game/ReplicatedStorage/Packages/RoguePropertyService"))

	-- Internal
	self._serviceBag:GetService(require("../Shared/SoundEffectService"))
end

function SoundGroupServiceClient.Destroy(self: SoundGroupServiceClient): ()
	self._maid:DoCleaning()
end

return SoundGroupServiceClient
