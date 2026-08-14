--!strict
--[=[
	Applies the local player's persisted key bindings and observes rebindable
	InputKeyMapLists for changes.

	@class InputKeyMapDataStoreServiceClient
	@client
]=]
const InputKeyMapDataStoreClientModel = require("./Client/InputKeyMapDataStoreClientModel")
const InputKeyMapDataStoreServiceConstants = require("./Shared/InputKeyMapDataStoreServiceConstants")
const InputKeyMapDataStoreServiceUtils = require("./Shared/InputKeyMapDataStoreServiceUtils")
const InputKeyMapRegistryServiceShared = require("@game/ReplicatedStorage/Packages/InputKeyMapRegistryServiceShared")
const InputKeyMapServiceClient = require("@game/ReplicatedStorage/Packages/InputKeyMapServiceClient")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const PlayerDataStoreServiceClient = require("@game/ReplicatedStorage/Packages/PlayerDataStoreServiceClient")
const PlayerDataStoreServiceProfile = require("@game/ReplicatedStorage/Packages/PlayerDataStoreServiceProfile")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

const InputKeyMapDataStoreServiceClient = {}
InputKeyMapDataStoreServiceClient.ServiceName = "InputKeyMapDataStoreServiceClient"

export type InputKeyMapDataStoreServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_inputKeyMapServiceClient: InputKeyMapServiceClient.InputKeyMapServiceClient,
		_inputKeyMapRegistryService: InputKeyMapRegistryServiceShared.InputKeyMapRegistryServiceShared,
		_playerDataStoreServiceClient: PlayerDataStoreServiceClient.PlayerDataStoreServiceClient,
	},
	{} :: typeof({ __index = InputKeyMapDataStoreServiceClient })
))

function InputKeyMapDataStoreServiceClient.Init(
	self: InputKeyMapDataStoreServiceClient,
	serviceBag: ServiceBag.ServiceBag
): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._inputKeyMapServiceClient = self._serviceBag:GetService(InputKeyMapServiceClient)
	self._inputKeyMapRegistryService = self._serviceBag:GetService(InputKeyMapRegistryServiceShared)

	const profileDefinition = PlayerDataStoreServiceProfile.Get()
	assert(
		InputKeyMapDataStoreServiceUtils.isCompatibleProfileDefinition(profileDefinition),
		`{PlayerDataStoreServiceProfile.GetName()}.Template must contain an {InputKeyMapDataStoreServiceConstants.PROFILE_PATH} array`
	)

	self._playerDataStoreServiceClient = self._serviceBag:GetService(PlayerDataStoreServiceClient)
end

function InputKeyMapDataStoreServiceClient.Start(self: InputKeyMapDataStoreServiceClient): ()
	self._maid:GiveTask(self._inputKeyMapRegistryService:ObserveProvidersBrio():Subscribe(function(providerBrio)
		if providerBrio:IsDead() then
			return
		end

		const providerMaid, provider = providerBrio:ToMaidAndValue()
		const providerName = provider:GetProviderName()

		providerMaid:GiveTask(provider:ObserveInputKeyMapListsBrio():Subscribe(function(listBrio)
			if listBrio:IsDead() then
				return
			end

			const listMaid, inputKeyMapList = listBrio:ToMaidAndValue()
			if inputKeyMapList:IsUserRebindable() then
				listMaid:GiveTask(
					InputKeyMapDataStoreClientModel.new(
						providerName,
						inputKeyMapList,
						self._playerDataStoreServiceClient
					)
				)
			end
		end))
	end))
end

function InputKeyMapDataStoreServiceClient.Destroy(self: InputKeyMapDataStoreServiceClient): ()
	self._maid:DoCleaning()
end

return InputKeyMapDataStoreServiceClient
