--!strict
--[=[
	Creates and observes the replicated Folder layout used by GameConfigService.

	@class GameConfigUtils
]=]

const require = require("../../../../Loader").load()

const AttributeUtils = require("AttributeUtils")
const Binder = require("Binder")
const Brio = require("Brio")
const GameConfigAssetTypeUtils = require("GameConfigAssetTypeUtils")
const GameConfigAssetTypes = require("GameConfigAssetTypes")
const GameConfigConstants = require("GameConfigConstants")
const Observable = require("Observable")
const RxInstanceUtils = require("RxInstanceUtils")

const GameConfigUtils = {}

--[=[
	Creates and binds a configuration for a universe game ID.

	@param binder Binder<GameConfigBase>
	@param gameId number
	@return Folder
]=]
function GameConfigUtils.create(binder: Binder.Binder<any>, gameId: number): Folder
	assert(Binder.isBinder(binder), "Bad binder")
	assert(type(gameId) == "number" and gameId >= 0 and gameId % 1 == 0, "Bad gameId")

	const config = Instance.new("Folder")
	config.Name = "GameConfig"
	AttributeUtils.initAttribute(config, GameConfigConstants.GAME_ID_ATTRIBUTE, gameId)

	for _, assetType in GameConfigAssetTypes:GetValues() do
		GameConfigUtils.getOrCreateAssetFolder(config, assetType)
	end

	binder:Bind(config)
	return config
end

--[=[
	Gets or creates the child folder for one asset category.

	@param config Folder
	@param assetType GameConfigAssetType
	@return Folder
]=]
function GameConfigUtils.getOrCreateAssetFolder(
	config: Folder,
	assetType: GameConfigAssetTypes.GameConfigAssetType
): Folder
	assert(typeof(config) == "Instance" and config:IsA("Folder"), "Bad config")
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")

	const folderName = GameConfigAssetTypeUtils.getPlural(assetType)
	const existing = config:FindFirstChild(folderName)
	if existing then
		assert(existing:IsA("Folder"), `{existing:GetFullName()} must be a Folder`)
		return existing
	end

	const folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = config
	return folder
end

--[=[
	Observes the current child folder for one asset category as a Brio.

	@param config Folder
	@param assetType GameConfigAssetType
	@return Observable<Brio<Folder>>
]=]
function GameConfigUtils.observeAssetFolderBrio(
	config: Folder,
	assetType: GameConfigAssetTypes.GameConfigAssetType
): Observable.Observable<Brio.Brio<Folder>>
	assert(typeof(config) == "Instance" and config:IsA("Folder"), "Bad config")
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")

	return RxInstanceUtils.observeLastNamedChildBrio(
			config,
			"Folder",
			GameConfigAssetTypeUtils.getPlural(assetType)
		) :: any
end

return GameConfigUtils
