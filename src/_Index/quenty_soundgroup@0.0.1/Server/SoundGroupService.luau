--!strict
--[=[
	@class SoundGroupService
]=]
local Maid = require("@game/ReplicatedStorage/Packages/Maid")
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
local WellKnownSoundGroups = require("../Shared/Groups/WellKnownSoundGroups")

local SoundGroupService = {}
SoundGroupService.ServiceName = "SoundGroupService"

export type SoundGroupService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_soundEffectService: any,
	},
	{} :: typeof({ __index = SoundGroupService })
))

function SoundGroupService.Init(self: SoundGroupService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	-- External
	self._serviceBag:GetService(require("@game/ReplicatedStorage/Packages/TieRealmService"))
	self._serviceBag:GetService(require("@game/ReplicatedStorage/Packages/RoguePropertyService"))

	-- Internal
	self._soundEffectService = self._serviceBag:GetService(require("../Shared/SoundEffectService"))
end

function SoundGroupService.Start(self: SoundGroupService): ()
	-- Ensure initial creation of these so server effects can work
	self._soundEffectService:GetOrCreateSoundGroup(WellKnownSoundGroups.MASTER)
	self._soundEffectService:GetOrCreateSoundGroup(WellKnownSoundGroups.SFX)
	self._soundEffectService:GetOrCreateSoundGroup(WellKnownSoundGroups.MUSIC)
	self._soundEffectService:GetOrCreateSoundGroup(WellKnownSoundGroups.VOICE)
end

function SoundGroupService.Destroy(self: SoundGroupService): ()
	self._maid:DoCleaning()
end

return SoundGroupService
