--!strict
--[=[
	Shared reactive model for one replicated game configuration.

	@class GameConfigBase
]=]

const require = require("../../../../Loader").load()

const AttributeValue = require("AttributeValue")
const BaseObject = require("BaseObject")
const Brio = require("Brio")
const GameConfigAssetBase = require("GameConfigAssetBase")
const GameConfigAssetTypeUtils = require("GameConfigAssetTypeUtils")
const GameConfigAssetTypes = require("GameConfigAssetTypes")
const GameConfigConstants = require("GameConfigConstants")
const GameConfigUtils = require("GameConfigUtils")
const Observable = require("Observable")
const ObservableMapSet = require("ObservableMapSet")
const Rx = require("Rx")
const RxBinderUtils = require("RxBinderUtils")
const RxBrioUtils = require("RxBrioUtils")
const RxInstanceUtils = require("RxInstanceUtils")

type AssetId = number | string
type AssetModel = GameConfigAssetBase.GameConfigAssetBase
type AssetType = GameConfigAssetTypes.GameConfigAssetType

const GameConfigBase = setmetatable({}, BaseObject)
GameConfigBase.ClassName = "GameConfigBase"
GameConfigBase.__index = GameConfigBase

export type GameConfigBase =
	typeof(setmetatable(
		{} :: {
			_obj: Folder,
			_gameId: AttributeValue.AttributeValue<number>,
			_setupObservation: boolean,
			_assetTypeToAssetConfig: any,
			_assetKeyToAssetConfig: any,
			_assetIdToAssetConfig: any,
			_assetTypeToAssetKeyMappings: { [AssetType]: any },
			_assetTypeToAssetIdMappings: { [AssetType]: any },
		},
		{} :: typeof({ __index = GameConfigBase })
	))
	& BaseObject.BaseObject<Folder>

--[=[
	Constructs the shared configuration model. Use the realm-specific binder to
	construct this class.

	@param folder Folder
	@return GameConfigBase
]=]
function GameConfigBase.new(folder: Folder): GameConfigBase
	assert(typeof(folder) == "Instance" and folder:IsA("Folder"), "Bad folder")

	const self = setmetatable(BaseObject.new(folder) :: any, GameConfigBase) :: GameConfigBase
	self._gameId = AttributeValue.new(folder, GameConfigConstants.GAME_ID_ATTRIBUTE, game.GameId)
	self._setupObservation = false

	self._assetTypeToAssetConfig = self._maid:Add(ObservableMapSet.new())
	self._assetKeyToAssetConfig = self._maid:Add(ObservableMapSet.new())
	self._assetIdToAssetConfig = self._maid:Add(ObservableMapSet.new())
	self._assetTypeToAssetKeyMappings = {}
	self._assetTypeToAssetIdMappings = {}

	for _, assetType in GameConfigAssetTypes:GetValues() do
		const keyMap = self._maid:Add(ObservableMapSet.new())
		const idMap = self._maid:Add(ObservableMapSet.new())
		self._assetTypeToAssetKeyMappings[assetType] = keyMap
		self._assetTypeToAssetIdMappings[assetType] = idMap

		self._maid:GiveTask(self._assetTypeToAssetConfig:ObserveItemsForKeyBrio(assetType):Subscribe(function(brio)
			if brio:IsDead() then
				return
			end

			const asset = brio:GetValue()
			const maid = brio:ToMaid()
			maid:GiveTask(keyMap:Push(asset:ObserveAssetKey(), asset))
			maid:GiveTask(idMap:Push(asset:ObserveAssetId(), asset))
		end))
	end

	return self
end

--[=[
	Returns the underlying replicated Folder.

	@return Folder
]=]
function GameConfigBase.GetFolder(self: GameConfigBase): Folder
	return self._obj
end

--[=[
	Returns this configuration's universe game ID.

	@return number
]=]
function GameConfigBase.GetGameId(self: GameConfigBase): number
	return self._gameId.Value
end

--[=[
	Observes this configuration's universe game ID.

	@return Observable<number>
]=]
function GameConfigBase.ObserveGameId(self: GameConfigBase): Observable.Observable<number>
	return self._gameId:Observe()
end

--[=[
	Returns this configuration's name.

	@return string
]=]
function GameConfigBase.GetConfigName(self: GameConfigBase): string
	return self._obj.Name
end

--[=[
	Observes this configuration's name.

	@return Observable<string>
]=]
function GameConfigBase.ObserveConfigName(self: GameConfigBase): Observable.Observable<string>
	return RxInstanceUtils.observeProperty(self._obj, "Name") :: any
end

--[=[
	Returns every asset of a type under this configuration.

	@param assetType GameConfigAssetType
	@return { GameConfigAssetBase }
]=]
function GameConfigBase.GetAssetsOfType(self: GameConfigBase, assetType: AssetType): { AssetModel }
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	return self._assetTypeToAssetConfig:GetListForKey(assetType)
end

--[=[
	Returns every asset matching a type and key.

	@param assetType GameConfigAssetType
	@param assetKey string
	@return { GameConfigAssetBase }
]=]
function GameConfigBase.GetAssetsOfTypeAndKey(
	self: GameConfigBase,
	assetType: AssetType,
	assetKey: string
): { AssetModel }
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetKey) == "string", "Bad assetKey")
	return self._assetTypeToAssetKeyMappings[assetType]:GetListForKey(assetKey)
end

--[=[
	Returns every asset matching a type and identifier.

	@param assetType GameConfigAssetType
	@param assetId GameConfigAssetId
	@return { GameConfigAssetBase }
]=]
function GameConfigBase.GetAssetsOfTypeAndId(
	self: GameConfigBase,
	assetType: AssetType,
	assetId: AssetId
): { AssetModel }
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetId) == "number" or type(assetId) == "string", "Bad assetId")
	return self._assetTypeToAssetIdMappings[assetType]:GetListForKey(assetId)
end

--[=[
	Observes assets matching a type and key as Brios.

	@param assetType GameConfigAssetType
	@param assetKey string
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigBase.ObserveAssetByTypeAndKeyBrio(
	self: GameConfigBase,
	assetType: AssetType,
	assetKey: string
): Observable.Observable<Brio.Brio<AssetModel>>
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetKey) == "string", "Bad assetKey")
	return self._assetTypeToAssetKeyMappings[assetType]:ObserveItemsForKeyBrio(assetKey)
end

--[=[
	Observes assets matching a type and identifier as Brios.

	@param assetType GameConfigAssetType
	@param assetId GameConfigAssetId
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigBase.ObserveAssetByTypeAndIdBrio(
	self: GameConfigBase,
	assetType: AssetType,
	assetId: AssetId
): Observable.Observable<Brio.Brio<AssetModel>>
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetId) == "number" or type(assetId) == "string", "Bad assetId")
	return self._assetTypeToAssetIdMappings[assetType]:ObserveItemsForKeyBrio(assetId)
end

--[=[
	Observes every asset matching an identifier as Brios.

	@param assetId GameConfigAssetId
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigBase.ObserveAssetByIdBrio(
	self: GameConfigBase,
	assetId: AssetId
): Observable.Observable<Brio.Brio<AssetModel>>
	assert(type(assetId) == "number" or type(assetId) == "string", "Bad assetId")
	return self._assetIdToAssetConfig:ObserveItemsForKeyBrio(assetId)
end

--[=[
	Observes every asset matching a key as Brios.

	@param assetKey string
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigBase.ObserveAssetByKeyBrio(
	self: GameConfigBase,
	assetKey: string
): Observable.Observable<Brio.Brio<AssetModel>>
	assert(type(assetKey) == "string", "Bad assetKey")
	return self._assetKeyToAssetConfig:ObserveItemsForKeyBrio(assetKey)
end

--[=[
	Observes every asset of a type as Brios.

	@param assetType GameConfigAssetType
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigBase.ObserveAssetByTypeBrio(
	self: GameConfigBase,
	assetType: AssetType
): Observable.Observable<Brio.Brio<AssetModel>>
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	return self._assetTypeToAssetConfig:ObserveItemsForKeyBrio(assetType)
end

--[=[
	Initializes child-asset observation. Realm-specific subclasses call this once
	the correct asset binder is available.
]=]
function GameConfigBase.InitObservation(self: GameConfigBase): ()
	if self._setupObservation then
		return
	end
	self._setupObservation = true

	const observables = {}
	for _, assetType in GameConfigAssetTypes:GetValues() do
		table.insert(
			observables,
			self:_observeAssetFolderBrio(assetType):Pipe({
				RxBrioUtils.switchMapBrio(function(folder)
					return RxBinderUtils.observeBoundChildClassBrio(self:GetGameConfigAssetBinder(), folder)
				end),
			})
		)
	end

	self._maid:GiveTask(Rx.merge(observables):Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		const asset = brio:GetValue()
		const maid = brio:ToMaid()
		maid:GiveTask(self._assetTypeToAssetConfig:Push(asset:ObserveAssetType(), asset))
		maid:GiveTask(self._assetKeyToAssetConfig:Push(asset:ObserveAssetKey(), asset))
		maid:GiveTask(self._assetIdToAssetConfig:Push(asset:ObserveAssetId(), asset))
	end))
end

function GameConfigBase.GetGameConfigAssetBinder(_self: GameConfigBase): any
	error("Not implemented")
end

function GameConfigBase._observeAssetFolderBrio(
	self: GameConfigBase,
	assetType: AssetType
): Observable.Observable<Brio.Brio<Folder>>
	return GameConfigUtils.observeAssetFolderBrio(self._obj, assetType)
end

return GameConfigBase
