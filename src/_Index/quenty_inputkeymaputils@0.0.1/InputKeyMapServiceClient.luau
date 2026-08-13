--!strict
--[=[
	@class InputKeyMapServiceClient
]=]
local InputKeyMapList = require("./Shared/InputKeyMapList")
local InputKeyMapRegistryServiceShared = require("./Shared/InputKeyMapRegistryServiceShared")
local Maid = require("@game/ReplicatedStorage/Packages/Maid")
local PseudoLocalize = require("@game/ReplicatedStorage/Packages/PseudoLocalize")
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local InputKeyMapServiceClient = {}
InputKeyMapServiceClient.ServiceName = "InputKeyMapServiceClient"

export type InputKeyMapServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_translator: any,
		_registryService: InputKeyMapRegistryServiceShared.InputKeyMapRegistryServiceShared,
	},
	{} :: typeof({ __index = InputKeyMapServiceClient })
))

function InputKeyMapServiceClient.Init(self: InputKeyMapServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	-- External
	self._serviceBag:GetService(require("@game/ReplicatedStorage/Packages/InputModeServiceClient"))

	-- Internal
	self._translator = self._serviceBag:GetService(require("./Shared/InputKeyMapTranslator"))
	self._registryService = self._serviceBag:GetService(require("./Shared/InputKeyMapRegistryServiceShared")) :: any

	self:_ensureLocalizationEntries()
end

function InputKeyMapServiceClient.FindInputKeyMapList(
	self: InputKeyMapServiceClient,
	providerName: string,
	listName: string
): InputKeyMapList.InputKeyMapList?
	return self._registryService:FindInputKeyMapList(providerName, listName)
end

function InputKeyMapServiceClient._ensureLocalizationEntries(self: InputKeyMapServiceClient): ()
	self._maid:GiveTask(self._registryService:ObserveInputKeyMapListsBrio():Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		local inputKeyMapList = brio:GetValue()

		local text = inputKeyMapList:GetBindingName()

		local localizationTable = self._translator:GetLocalizationTable()
		local key = inputKeyMapList:GetBindingTranslationKey()
		local source = text
		local context = string.format("InputKeyMapServiceClient.%s", inputKeyMapList:GetListName())
		local localeId = "en"
		local value = text

		localizationTable:SetEntryValue(key, source, context, localeId, value)
		localizationTable:SetEntryValue(
			key,
			source,
			context,
			PseudoLocalize.getDefaultPseudoLocaleId(),
			PseudoLocalize.pseudoLocalize(value)
		)
	end))
end

function InputKeyMapServiceClient.Destroy(self: InputKeyMapServiceClient): ()
	self._maid:DoCleaning()
end

return InputKeyMapServiceClient
