--!strict
--[=[
	Provides synchronous, promise-based, and reactive queries over all replicated
	game configurations that target the current universe.

	@class GameConfigPicker
]=]

const require = require("../../../../Loader").load()

const BaseObject = require("BaseObject")
const Binder = require("Binder")
const Brio = require("Brio")
const GameConfigAssetBase = require("GameConfigAssetBase")
const GameConfigAssetTypeUtils = require("GameConfigAssetTypeUtils")
const GameConfigAssetTypes = require("GameConfigAssetTypes")
const GameConfigAssetUtils = require("GameConfigAssetUtils")
const Observable = require("Observable")
const ObservableMapSet = require("ObservableMapSet")
const Promise = require("Promise")
const RxBinderUtils = require("RxBinderUtils")
const RxBrioUtils = require("RxBrioUtils")
const ServiceBag = require("ServiceBag")

type AssetId = number | string
type AssetModel = GameConfigAssetBase.GameConfigAssetBase
type AssetType = GameConfigAssetTypes.GameConfigAssetType
type ConfigModel = any

const GameConfigPicker = setmetatable({}, BaseObject)
GameConfigPicker.ClassName = "GameConfigPicker"
GameConfigPicker.__index = GameConfigPicker

export type GameConfigPicker =
	typeof(setmetatable(
		{} :: {
			_serviceBag: ServiceBag.ServiceBag,
			_gameConfigBinder: Binder.Binder<any>,
			_gameConfigAssetBinder: Binder.Binder<any>,
			_gameIdToConfigSet: any,
		},
		{} :: typeof({ __index = GameConfigPicker })
	))
	& BaseObject.BaseObject<nil>

--[=[
	Constructs a picker backed by the realm's configuration binders. Retrieve the
	shared picker from GameConfigService or GameConfigServiceClient in normal use.

	@param serviceBag ServiceBag
	@param gameConfigBinder Binder<GameConfigBase>
	@param gameConfigAssetBinder Binder<GameConfigAssetBase>
	@return GameConfigPicker
]=]
function GameConfigPicker.new(
	serviceBag: ServiceBag.ServiceBag,
	gameConfigBinder: Binder.Binder<any>,
	gameConfigAssetBinder: Binder.Binder<any>
): GameConfigPicker
	assert(serviceBag, "No serviceBag")
	assert(Binder.isBinder(gameConfigBinder), "Bad gameConfigBinder")
	assert(Binder.isBinder(gameConfigAssetBinder), "Bad gameConfigAssetBinder")

	const self = setmetatable(BaseObject.new() :: any, GameConfigPicker) :: GameConfigPicker
	self._serviceBag = serviceBag
	self._gameConfigBinder = gameConfigBinder
	self._gameConfigAssetBinder = gameConfigAssetBinder
	self._gameIdToConfigSet = self._maid:Add(ObservableMapSet.new())

	self._maid:GiveTask(RxBinderUtils.observeAllBrio(gameConfigBinder):Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		const config = brio:GetValue()
		brio:ToMaid():GiveTask(self._gameIdToConfigSet:Push(config:ObserveGameId(), config))
	end))

	return self
end

--[=[
	Returns all configurations targeting the current universe.

	@return { GameConfigBase }
]=]
function GameConfigPicker.GetActiveConfigs(self: GameConfigPicker): { ConfigModel }
	return self:GetConfigsForGameId(game.GameId)
end

--[=[
	Returns all configurations targeting a specific universe game ID.

	@param gameId number
	@return { GameConfigBase }
]=]
function GameConfigPicker.GetConfigsForGameId(self: GameConfigPicker, gameId: number): { ConfigModel }
	assert(type(gameId) == "number" and gameId >= 0 and gameId % 1 == 0, "Bad gameId")
	return self._gameIdToConfigSet:GetListForKey(gameId)
end

--[=[
	Observes active configurations as Brios.

	@return Observable<Brio<GameConfigBase>>
]=]
function GameConfigPicker.ObserveActiveConfigsBrio(
	self: GameConfigPicker
): Observable.Observable<Brio.Brio<ConfigModel>>
	return self:ObserveConfigsForGameIdBrio(game.GameId)
end

--[=[
	Observes configurations targeting a specific universe game ID as Brios.

	@param gameId number
	@return Observable<Brio<GameConfigBase>>
]=]
function GameConfigPicker.ObserveConfigsForGameIdBrio(
	self: GameConfigPicker,
	gameId: number
): Observable.Observable<Brio.Brio<ConfigModel>>
	assert(type(gameId) == "number" and gameId >= 0 and gameId % 1 == 0, "Bad gameId")
	return self._gameIdToConfigSet:ObserveItemsForKeyBrio(gameId)
end

--[=[
	Returns every active asset of a type.

	@param assetType GameConfigAssetType
	@return { GameConfigAssetBase }
]=]
function GameConfigPicker.GetAllActiveAssetsOfType(self: GameConfigPicker, assetType: AssetType): { AssetModel }
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")

	const assets = {}
	for _, config in self:GetActiveConfigs() do
		for _, asset in config:GetAssetsOfType(assetType) do
			table.insert(assets, asset)
		end
	end
	return assets
end

--[=[
	Finds the first active asset matching a type and identifier.

	@param assetType GameConfigAssetType
	@param assetId GameConfigAssetId
	@return GameConfigAssetBase?
]=]
function GameConfigPicker.FindFirstActiveAssetOfId(
	self: GameConfigPicker,
	assetType: AssetType,
	assetId: AssetId
): AssetModel?
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetId) == "number" or type(assetId) == "string", "Bad assetId")

	for _, config in self:GetActiveConfigs() do
		const asset = config:GetAssetsOfTypeAndId(assetType, assetId)[1]
		if asset then
			return asset
		end
	end
	return nil
end

--[=[
	Finds the first active asset matching a type and key.

	@param assetType GameConfigAssetType
	@param assetKey string
	@return GameConfigAssetBase?
]=]
function GameConfigPicker.FindFirstActiveAssetOfKey(
	self: GameConfigPicker,
	assetType: AssetType,
	assetKey: string
): AssetModel?
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetKey) == "string", "Bad assetKey")

	for _, config in self:GetActiveConfigs() do
		const asset = config:GetAssetsOfTypeAndKey(assetType, assetKey)[1]
		if asset then
			return asset
		end
	end
	return nil
end

--[=[
	Observes every active asset of a type as Brios.

	@param assetType GameConfigAssetType
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigPicker.ObserveActiveAssetOfTypeBrio(
	self: GameConfigPicker,
	assetType: AssetType
): Observable.Observable<Brio.Brio<AssetModel>>
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")

	return self:ObserveActiveConfigsBrio():Pipe({
		RxBrioUtils.flatMapBrio(function(config)
			return config:ObserveAssetByTypeBrio(assetType)
		end),
	}) :: any
end

--[=[
	Observes every active asset matching a type and key as Brios.

	@param assetType GameConfigAssetType
	@param assetKey string
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigPicker.ObserveActiveAssetOfAssetTypeAndKeyBrio(
	self: GameConfigPicker,
	assetType: AssetType,
	assetKey: string
): Observable.Observable<Brio.Brio<AssetModel>>
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetKey) == "string", "Bad assetKey")

	return self:ObserveActiveConfigsBrio():Pipe({
		RxBrioUtils.flatMapBrio(function(config)
			return config:ObserveAssetByTypeAndKeyBrio(assetType, assetKey)
		end),
	}) :: any
end

--[=[
	Observes every active asset matching a type and identifier as Brios.

	@param assetType GameConfigAssetType
	@param assetId GameConfigAssetId
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigPicker.ObserveActiveAssetOfAssetTypeAndIdBrio(
	self: GameConfigPicker,
	assetType: AssetType,
	assetId: AssetId
): Observable.Observable<Brio.Brio<AssetModel>>
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetId) == "number" or type(assetId) == "string", "Bad assetId")

	return self:ObserveActiveConfigsBrio():Pipe({
		RxBrioUtils.flatMapBrio(function(config)
			return config:ObserveAssetByTypeAndIdBrio(assetType, assetId)
		end),
	}) :: any
end

--[=[
	Observes every active asset matching an identifier as Brios.

	@param assetId GameConfigAssetId
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigPicker.ObserveActiveAssetOfAssetIdBrio(
	self: GameConfigPicker,
	assetId: AssetId
): Observable.Observable<Brio.Brio<AssetModel>>
	assert(type(assetId) == "number" or type(assetId) == "string", "Bad assetId")

	return self:ObserveActiveConfigsBrio():Pipe({
		RxBrioUtils.flatMapBrio(function(config)
			return config:ObserveAssetByIdBrio(assetId)
		end),
	}) :: any
end

--[=[
	Observes every active asset matching a key as Brios.

	@param assetKey string
	@return Observable<Brio<GameConfigAssetBase>>
]=]
function GameConfigPicker.ObserveActiveAssetOfKeyBrio(
	self: GameConfigPicker,
	assetKey: string
): Observable.Observable<Brio.Brio<AssetModel>>
	assert(type(assetKey) == "string", "Bad assetKey")

	return self:ObserveActiveConfigsBrio():Pipe({
		RxBrioUtils.flatMapBrio(function(config)
			return config:ObserveAssetByKeyBrio(assetKey)
		end),
	}) :: any
end

--[=[
	Converts a configured key or direct identifier into an asset identifier.

	@param assetType GameConfigAssetType
	@param assetIdOrKey GameConfigAssetId
	@return GameConfigAssetId?
]=]
function GameConfigPicker.ToAssetId(self: GameConfigPicker, assetType: AssetType, assetIdOrKey: AssetId): AssetId?
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetIdOrKey) == "number" or type(assetIdOrKey) == "string", "Bad assetIdOrKey")

	if type(assetIdOrKey) == "string" then
		const asset = self:FindFirstActiveAssetOfKey(assetType, assetIdOrKey)
		if asset then
			return asset:GetAssetId()
		end

		if assetType == GameConfigAssetTypes.SUBSCRIPTION or assetType == GameConfigAssetTypes.MEMBERSHIP then
			return assetIdOrKey
		end
		return nil
	end
	return assetIdOrKey
end

--[=[
	Observes conversion of a configured key or direct identifier as Brios.

	@param assetType GameConfigAssetType
	@param assetIdOrKey GameConfigAssetId
	@return Observable<Brio<GameConfigAssetId>>
]=]
function GameConfigPicker.ObserveToAssetIdBrio(
	self: GameConfigPicker,
	assetType: AssetType,
	assetIdOrKey: AssetId
): Observable.Observable<Brio.Brio<AssetId>>
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetIdOrKey) == "number" or type(assetIdOrKey) == "string", "Bad assetIdOrKey")

	if type(assetIdOrKey) == "number" then
		return RxBrioUtils.of(assetIdOrKey) :: any
	end
	if
		(assetType == GameConfigAssetTypes.SUBSCRIPTION or assetType == GameConfigAssetTypes.MEMBERSHIP)
		and not self:FindFirstActiveAssetOfKey(assetType, assetIdOrKey)
	then
		return RxBrioUtils.of(assetIdOrKey) :: any
	end

	return self:ObserveActiveAssetOfAssetTypeAndKeyBrio(assetType, assetIdOrKey):Pipe({
		RxBrioUtils.switchMapBrio(function(asset)
			return asset:ObserveAssetId()
		end),
	}) :: any
end

--[=[
	Promises the current Robux price for a configured key or numeric Roblox ID.

	@param assetType GameConfigAssetType
	@param assetIdOrKey number | string
	@return Promise<number?>
]=]
function GameConfigPicker.PromisePriceInRobux(
	self: GameConfigPicker,
	assetType: AssetType,
	assetIdOrKey: number | string
): Promise.Promise<number?>
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetIdOrKey) == "number" or type(assetIdOrKey) == "string", "Bad assetIdOrKey")

	if type(assetIdOrKey) == "string" then
		const asset = self:FindFirstActiveAssetOfKey(assetType, assetIdOrKey)
		if not asset then
			return Promise.rejected(`No active {assetType} asset uses key {assetIdOrKey}`)
		end
		return asset:PromiseCloudPriceInRobux()
	end

	const configuredAsset = self:FindFirstActiveAssetOfId(assetType, assetIdOrKey)
	if configuredAsset then
		return configuredAsset:PromiseCloudPriceInRobux()
	end

	return GameConfigAssetUtils.promiseCloudDataForAssetType(self._serviceBag, assetType, assetIdOrKey)
		:Then(function(cloudData)
			if type(cloudData) == "table" and type(cloudData.PriceInRobux) == "number" then
				return cloudData.PriceInRobux
			end
			return nil :: number?
		end)
end

return GameConfigPicker
