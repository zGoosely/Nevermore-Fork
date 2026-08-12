--!strict
--[=[
	Server model for a configured asset. It derives stable localization keys from
	Roblox cloud metadata and stores those keys on the replicated asset Folder.

	@class GameConfigAsset
	@server
]=]

const require = require("../../../../Loader").load()

const GameConfigAssetBase = require("GameConfigAssetBase")
const GameConfigTranslator = require("GameConfigTranslator")
const JSONTranslator = require("JSONTranslator")
const Rx = require("Rx")
const ServiceBag = require("ServiceBag")

const GameConfigAsset = setmetatable({}, GameConfigAssetBase)
GameConfigAsset.ClassName = "GameConfigAsset"
GameConfigAsset.__index = GameConfigAsset

export type GameConfigAsset =
	typeof(setmetatable(
		{} :: {
			_serviceBag: ServiceBag.ServiceBag,
			_translator: JSONTranslator.JSONTranslator,
		},
		{} :: typeof({ __index = GameConfigAsset })
	))
	& GameConfigAssetBase.GameConfigAssetBase

--[=[
	Constructs the server asset model. Called automatically by the server binder.

	@param folder Folder
	@param serviceBag ServiceBag
	@return GameConfigAsset
]=]
function GameConfigAsset.new(folder: Folder, serviceBag: ServiceBag.ServiceBag): GameConfigAsset
	const self = setmetatable(GameConfigAssetBase.new(folder, serviceBag) :: any, GameConfigAsset) :: GameConfigAsset
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._translator = self._serviceBag:GetService(GameConfigTranslator)

	self._maid:GiveTask(Rx.combineLatest({
		assetKey = self:ObserveAssetKey(),
		assetType = self:ObserveAssetType(),
		text = self:ObserveCloudName(),
	}):Subscribe(function(state)
		if type(state.text) == "string" and state.text ~= "" and type(state.assetType) == "string" then
			const prefix = `assets.{state.assetType}.{state.assetKey}.name`
			self:SetNameTranslationKey(self._translator:ToTranslationKey(prefix, state.text))
		else
			self:SetNameTranslationKey(nil)
		end
	end))

	self._maid:GiveTask(Rx.combineLatest({
		assetKey = self:ObserveAssetKey(),
		assetType = self:ObserveAssetType(),
		text = self:ObserveCloudDescription(),
	}):Subscribe(function(state)
		if type(state.text) == "string" and state.text ~= "" and type(state.assetType) == "string" then
			const prefix = `assets.{state.assetType}.{state.assetKey}.description`
			self:SetDescriptionTranslationKey(self._translator:ToTranslationKey(prefix, state.text))
		else
			self:SetDescriptionTranslationKey(nil)
		end
	end))

	return self
end

return GameConfigAsset
