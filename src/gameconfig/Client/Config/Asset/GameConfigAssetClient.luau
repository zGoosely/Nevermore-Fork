--!strict
--[=[
	Client model for a replicated configured asset.

	@class GameConfigAssetClient
	@client
]=]

const require = require("../../../../Loader").load()

const GameConfigAssetBase = require("GameConfigAssetBase")
const GameConfigTranslator = require("GameConfigTranslator")
const JSONTranslator = require("JSONTranslator")
const Observable = require("Observable")
const Rx = require("Rx")
const ServiceBag = require("ServiceBag")

const GameConfigAssetClient = setmetatable({}, GameConfigAssetBase)
GameConfigAssetClient.ClassName = "GameConfigAssetClient"
GameConfigAssetClient.__index = GameConfigAssetClient

export type GameConfigAssetClient =
	typeof(setmetatable(
		{} :: {
			_serviceBag: ServiceBag.ServiceBag,
			_configTranslator: JSONTranslator.JSONTranslator,
		},
		{} :: typeof({ __index = GameConfigAssetClient })
	))
	& GameConfigAssetBase.GameConfigAssetBase

--[=[
	Constructs the client asset model. Called automatically by the client binder.

	@param folder Folder
	@param serviceBag ServiceBag
	@return GameConfigAssetClient
]=]
function GameConfigAssetClient.new(folder: Folder, serviceBag: ServiceBag.ServiceBag): GameConfigAssetClient
	const self =
		setmetatable(GameConfigAssetBase.new(folder, serviceBag) :: any, GameConfigAssetClient) :: GameConfigAssetClient
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._configTranslator = self._serviceBag:GetService(GameConfigTranslator)
	return self
end

--[=[
	Observes and localizes the cloud name. Cloud data is fetched lazily only when
	the translated name is observed.

	@return Observable<string>
]=]
function GameConfigAssetClient.ObserveTranslatedName(self: GameConfigAssetClient): Observable.Observable<string>
	return Rx.combineLatest({
		assetKey = self:ObserveAssetKey(),
		assetType = self:ObserveAssetType(),
		text = self:ObserveCloudName(),
	}):Pipe({
		Rx.switchMap(function(state): any
			if type(state.assetType) == "string" and type(state.text) == "string" and state.text ~= "" then
				return self._configTranslator:ObserveTranslation(
					`assets.{state.assetType}.{state.assetKey}.name`,
					state.text
				)
			end
			return GameConfigAssetBase.ObserveTranslatedName(self)
		end),
	}) :: any
end

--[=[
	Observes and localizes the cloud description. Cloud data is fetched lazily
	only when the translated description is observed.

	@return Observable<string>
]=]
function GameConfigAssetClient.ObserveTranslatedDescription(self: GameConfigAssetClient): Observable.Observable<string>
	return Rx.combineLatest({
		assetKey = self:ObserveAssetKey(),
		assetType = self:ObserveAssetType(),
		text = self:ObserveCloudDescription(),
	}):Pipe({
		Rx.switchMap(function(state): any
			if type(state.assetType) == "string" and type(state.text) == "string" and state.text ~= "" then
				return self._configTranslator:ObserveTranslation(
					`assets.{state.assetType}.{state.assetKey}.description`,
					state.text
				)
			end
			return GameConfigAssetBase.ObserveTranslatedDescription(self)
		end),
	}) :: any
end

return GameConfigAssetClient
