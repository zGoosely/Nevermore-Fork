--!strict
--[=[
	Shared reactive model for a configured Roblox asset. Instances of this class
	are constructed by the server and client binders.

	@class GameConfigAssetBase
]=]

const require = require("../../../../Loader").load()

const AttributeValue = require("AttributeValue")
const BaseObject = require("BaseObject")
const CancelToken = require("CancelToken")
const GameConfigAssetConstants = require("GameConfigAssetConstants")
const GameConfigAssetTypes = require("GameConfigAssetTypes")
const GameConfigAssetUtils = require("GameConfigAssetUtils")
const GameConfigTranslator = require("GameConfigTranslator")
const JSONTranslator = require("JSONTranslator")
const Observable = require("Observable")
const Promise = require("Promise")
const Rx = require("Rx")
const RxAttributeUtils = require("RxAttributeUtils")
const RxInstanceUtils = require("RxInstanceUtils")
const ServiceBag = require("ServiceBag")

export type GameConfigAssetId = number | string
export type GameConfigAssetState = {
	assetId: GameConfigAssetId,
	assetKey: string,
	assetType: GameConfigAssetTypes.GameConfigAssetType,
}

const UNKNOWN_NAME_KEY = "assets.name.unknown"
const UNKNOWN_DESCRIPTION_KEY = "assets.description.unknown"

const GameConfigAssetBase = setmetatable({}, BaseObject)
GameConfigAssetBase.ClassName = "GameConfigAssetBase"
GameConfigAssetBase.__index = GameConfigAssetBase

export type GameConfigAssetBase =
	typeof(setmetatable(
		{} :: {
			_obj: Folder,
			_serviceBag: ServiceBag.ServiceBag,
			_nameTranslationKey: AttributeValue.AttributeValue<string>,
			_descriptionTranslationKey: AttributeValue.AttributeValue<string>,
			_configTranslator: JSONTranslator.JSONTranslator,
			_cloudDataObservable: Observable.Observable<any?>?,
		},
		{} :: typeof({ __index = GameConfigAssetBase })
	))
	& BaseObject.BaseObject<Folder>

--[=[
	Constructs the shared asset model. Use GameConfigBindersServer or
	GameConfigBindersClient instead of constructing this directly.

	@param folder Folder
	@param serviceBag ServiceBag
	@return GameConfigAssetBase
]=]
function GameConfigAssetBase.new(folder: Folder, serviceBag: ServiceBag.ServiceBag): GameConfigAssetBase
	assert(typeof(folder) == "Instance" and folder:IsA("Folder"), "Bad folder")

	const self = setmetatable(BaseObject.new(folder) :: any, GameConfigAssetBase) :: GameConfigAssetBase
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._nameTranslationKey =
		AttributeValue.new(folder, GameConfigAssetConstants.NAME_TRANSLATION_KEY_ATTRIBUTE, UNKNOWN_NAME_KEY)
	self._descriptionTranslationKey = AttributeValue.new(
		folder,
		GameConfigAssetConstants.DESCRIPTION_TRANSLATION_KEY_ATTRIBUTE,
		UNKNOWN_DESCRIPTION_KEY
	)
	self._configTranslator = self._serviceBag:GetService(GameConfigTranslator)
	self._cloudDataObservable = nil

	return self
end

--[=[
	Returns the underlying replicated Folder.

	@return Folder
]=]
function GameConfigAssetBase.GetFolder(self: GameConfigAssetBase): Folder
	return self._obj
end

--[=[
	Returns the configured asset identifier.

	@return GameConfigAssetId
]=]
function GameConfigAssetBase.GetAssetId(self: GameConfigAssetBase): GameConfigAssetId
	const assetId = self._obj:GetAttribute(GameConfigAssetConstants.ASSET_ID_ATTRIBUTE)
	assert(type(assetId) == "number" or type(assetId) == "string", "Asset has no valid AssetId attribute")
	return assetId
end

--[=[
	Observes the configured asset identifier.

	@return Observable<GameConfigAssetId>
]=]
function GameConfigAssetBase.ObserveAssetId(self: GameConfigAssetBase): Observable.Observable<GameConfigAssetId>
	return RxAttributeUtils.observeAttribute(self._obj, GameConfigAssetConstants.ASSET_ID_ATTRIBUTE, nil) :: any
end

--[=[
	Returns the configured asset type, or nil while an incomplete instance is
	replicating.

	@return GameConfigAssetType?
]=]
function GameConfigAssetBase.GetAssetType(self: GameConfigAssetBase): GameConfigAssetTypes.GameConfigAssetType?
	const assetType = self._obj:GetAttribute(GameConfigAssetConstants.ASSET_TYPE_ATTRIBUTE)
	if GameConfigAssetTypes:IsValue(assetType) then
		return assetType :: GameConfigAssetTypes.GameConfigAssetType
	end
	return nil
end

--[=[
	Observes the configured asset type.

	@return Observable<GameConfigAssetType?>
]=]
function GameConfigAssetBase.ObserveAssetType(
	self: GameConfigAssetBase
): Observable.Observable<GameConfigAssetTypes.GameConfigAssetType?>
	return RxAttributeUtils.observeAttribute(self._obj, GameConfigAssetConstants.ASSET_TYPE_ATTRIBUTE, nil) :: any
end

--[=[
	Returns the stable lookup key for this asset.

	@return string
]=]
function GameConfigAssetBase.GetAssetKey(self: GameConfigAssetBase): string
	return self._obj.Name
end

--[=[
	Observes the stable lookup key for this asset.

	@return Observable<string>
]=]
function GameConfigAssetBase.ObserveAssetKey(self: GameConfigAssetBase): Observable.Observable<string>
	return RxInstanceUtils.observeProperty(self._obj, "Name") :: any
end

--[=[
	Observes the asset identifier, key, and type as one state object.

	@return Observable<GameConfigAssetState>
]=]
function GameConfigAssetBase.ObserveState(self: GameConfigAssetBase): Observable.Observable<GameConfigAssetState>
	return Rx.combineLatest({
		assetId = self:ObserveAssetId(),
		assetKey = self:ObserveAssetKey(),
		assetType = self:ObserveAssetType(),
	}) :: any
end

--[=[
	Sets the localization key used for the asset name. Passing nil restores the
	unknown fallback.

	@param nameTranslationKey string?
]=]
function GameConfigAssetBase.SetNameTranslationKey(self: GameConfigAssetBase, nameTranslationKey: string?): ()
	assert(type(nameTranslationKey) == "string" or nameTranslationKey == nil, "Bad nameTranslationKey")
	self._nameTranslationKey.Value = nameTranslationKey or UNKNOWN_NAME_KEY
end

--[=[
	Sets the localization key used for the asset description. Passing nil restores
	the unknown fallback.

	@param descriptionTranslationKey string?
]=]
function GameConfigAssetBase.SetDescriptionTranslationKey(
	self: GameConfigAssetBase,
	descriptionTranslationKey: string?
): ()
	assert(
		type(descriptionTranslationKey) == "string" or descriptionTranslationKey == nil,
		"Bad descriptionTranslationKey"
	)
	self._descriptionTranslationKey.Value = descriptionTranslationKey or UNKNOWN_DESCRIPTION_KEY
end

--[=[
	Observes the name localization key.

	@return Observable<string>
]=]
function GameConfigAssetBase.ObserveNameTranslationKey(self: GameConfigAssetBase): Observable.Observable<string>
	return self._nameTranslationKey:Observe()
end

--[=[
	Observes the description localization key.

	@return Observable<string>
]=]
function GameConfigAssetBase.ObserveDescriptionTranslationKey(self: GameConfigAssetBase): Observable.Observable<string>
	return self._descriptionTranslationKey:Observe()
end

--[=[
	Observes the localized asset name.

	@return Observable<string>
]=]
function GameConfigAssetBase.ObserveTranslatedName(self: GameConfigAssetBase): Observable.Observable<string>
	return self:ObserveNameTranslationKey():Pipe({
		Rx.switchMap(function(key)
			return self._configTranslator:ObserveFormatByKey(key)
		end),
	}) :: any
end

--[=[
	Observes the localized asset description.

	@return Observable<string>
]=]
function GameConfigAssetBase.ObserveTranslatedDescription(self: GameConfigAssetBase): Observable.Observable<string>
	return self:ObserveDescriptionTranslationKey():Pipe({
		Rx.switchMap(function(key)
			return self._configTranslator:ObserveFormatByKey(key)
		end),
	}) :: any
end

--[=[
	Promises the next name localization key.

	@param cancelToken CancelToken?
	@return Promise<string>
]=]
function GameConfigAssetBase.PromiseNameTranslationKey(
	self: GameConfigAssetBase,
	cancelToken: CancelToken.CancelToken?
): Promise.Promise<string>
	return Rx.toPromise(self:ObserveNameTranslationKey(), cancelToken)
end

--[=[
	Observes the name returned by Roblox cloud metadata.

	@return Observable<string?>
]=]
function GameConfigAssetBase.ObserveCloudName(self: GameConfigAssetBase): Observable.Observable<string?>
	return self:_observeCloudProperty({ "Name" }, "string")
end

--[=[
	Observes the description returned by Roblox cloud metadata.

	@return Observable<string?>
]=]
function GameConfigAssetBase.ObserveCloudDescription(self: GameConfigAssetBase): Observable.Observable<string?>
	return self:_observeCloudProperty({ "Description" }, "string")
end

--[=[
	Observes the Robux price returned by Roblox cloud metadata.

	@return Observable<number?>
]=]
function GameConfigAssetBase.ObserveCloudPriceInRobux(self: GameConfigAssetBase): Observable.Observable<number?>
	return self:_observeCloudProperty({ "PriceInRobux" }, "number")
end

--[=[
	Observes the icon asset ID returned by Roblox cloud metadata.

	@return Observable<number?>
]=]
function GameConfigAssetBase.ObserveCloudIconImageAssetId(self: GameConfigAssetBase): Observable.Observable<number?>
	return self:_observeCloudProperty({ "IconImageAssetId", "IconImageId" }, "number")
end

--[=[
	Promises the next cloud name.

	@param cancelToken CancelToken?
	@return Promise<string?>
]=]
function GameConfigAssetBase.PromiseCloudName(
	self: GameConfigAssetBase,
	cancelToken: CancelToken.CancelToken?
): Promise.Promise<string?>
	return Rx.toPromise(self:ObserveCloudName(), cancelToken)
end

--[=[
	Promises the next cloud price in Robux.

	@param cancelToken CancelToken?
	@return Promise<number?>
]=]
function GameConfigAssetBase.PromiseCloudPriceInRobux(
	self: GameConfigAssetBase,
	cancelToken: CancelToken.CancelToken?
): Promise.Promise<number?>
	return Rx.toPromise(self:ObserveCloudPriceInRobux(), cancelToken)
end

--[=[
	Promises the display color associated with this asset.

	@param cancelToken CancelToken?
	@return Promise<Color3>
]=]
function GameConfigAssetBase.PromiseColor(
	_self: GameConfigAssetBase,
	_cancelToken: CancelToken.CancelToken?
): Promise.Promise<Color3>
	return Promise.resolved(Color3.fromRGB(66, 158, 166))
end

function GameConfigAssetBase._observeCloudProperty(
	self: GameConfigAssetBase,
	propertyNames: { string },
	expectedType: string
): Observable.Observable<any?>
	assert(type(propertyNames) == "table", "Bad propertyNames")
	assert(type(expectedType) == "string", "Bad expectedType")

	return self:_observeCloudDataFromState():Pipe({
		Rx.map(function(data)
			if type(data) ~= "table" then
				return nil
			end

			for _, propertyName in propertyNames do
				const value = data[propertyName]
				if type(value) == expectedType then
					return value
				end
			end

			return nil
		end),
	})
end

function GameConfigAssetBase._observeCloudDataFromState(self: GameConfigAssetBase): Observable.Observable<any?>
	if self._cloudDataObservable then
		return self._cloudDataObservable
	end

	self._cloudDataObservable = self:ObserveState():Pipe({
		Rx.switchMap(function(state): any
			if
				GameConfigAssetTypes:IsValue(state.assetType)
				and type(state.assetKey) == "string"
				and GameConfigAssetUtils.isValidAssetId(state.assetType, state.assetId)
			then
				return Rx.fromPromise(self:_promiseCloudDataForState(state)):Pipe({
					Rx.catchError(function(err)
						warn(
							`[GameConfigAssetBase] Failed to load cloud metadata for {state.assetType} {tostring(
								state.assetId
							)}: {tostring(err)}`
						)
						return Rx.of(nil)
					end),
				})
			end

			return Rx.of(nil)
		end),
		Rx.distinct() :: any,
		Rx.shareReplay(1) :: any,
	}) :: any

	return self._cloudDataObservable
end

function GameConfigAssetBase._promiseCloudDataForState(
	self: GameConfigAssetBase,
	state: GameConfigAssetState
): Promise.Promise<any?>
	return GameConfigAssetUtils.promiseCloudDataForAssetType(self._serviceBag, state.assetType, state.assetId)
end

return GameConfigAssetBase
