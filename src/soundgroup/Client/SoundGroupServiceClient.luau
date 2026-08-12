--!strict
--[=[
	@class SoundGroupServiceClient
]=]

local require = require("../../Loader").load()

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")

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
	self._serviceBag:GetService(require("TieRealmService"))
	self._serviceBag:GetService(require("RoguePropertyService"))

	-- Internal
	self._serviceBag:GetService(require("SoundEffectService"))
end

function SoundGroupServiceClient.Destroy(self: SoundGroupServiceClient): ()
	self._maid:DoCleaning()
end

return SoundGroupServiceClient
