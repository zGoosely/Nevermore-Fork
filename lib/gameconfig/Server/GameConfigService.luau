--!strict
--[=[
	Registers Roblox assets into replicated, queryable game configurations.

	Configuration is represented by tagged Folders and attributes under
	ReplicatedStorage.GameConfigs, so additions and removals naturally replicate
	to GameConfigServiceClient without a custom network packet.

	@class GameConfigService
	@server
]=]

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const require = require("../../Loader").load()

const GameConfigAssetConstants = require("GameConfigAssetConstants")
const GameConfigAssetTypeUtils = require("GameConfigAssetTypeUtils")
const GameConfigAssetTypes = require("GameConfigAssetTypes")
const GameConfigAssetUtils = require("GameConfigAssetUtils")
const GameConfigConstants = require("GameConfigConstants")
const GameConfigDataService = require("GameConfigDataService")
const GameConfigPicker = require("GameConfigPicker")
const GameConfigServiceConstants = require("GameConfigServiceConstants")
const GameConfigTranslator = require("GameConfigTranslator")
const GameConfigUtils = require("GameConfigUtils")
const Maid = require("Maid")
const MarketplaceServiceCache = require("MarketplaceServiceCache")
const PreferredParentUtils = require("PreferredParentUtils")
const ServiceBag = require("ServiceBag")

type AssetId = number | string
type AssetType = GameConfigAssetTypes.GameConfigAssetType

const GameConfigService = {}
GameConfigService.ServiceName = "GameConfigService"
GameConfigService.ServerOnly = true

export type GameConfigService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_binders: any,
		_configPicker: GameConfigPicker.GameConfigPicker,
		_getPreferredParent: () -> Instance?,
	},
	{} :: typeof({ __index = GameConfigService })
))

function GameConfigService.Init(self: GameConfigService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	self._serviceBag:GetService(MarketplaceServiceCache)
	self._serviceBag:GetService(GameConfigTranslator)
	self._binders = self._serviceBag:GetService(require("GameConfigBindersServer"))
	self._configPicker =
		self._maid:Add(GameConfigPicker.new(self._serviceBag, self._binders.GameConfig, self._binders.GameConfigAsset))
	self._getPreferredParent = PreferredParentUtils.createPreferredParentRetriever(
		ReplicatedStorage,
		GameConfigServiceConstants.CONFIG_CONTAINER_NAME,
		true
	)

	const dataService = self._serviceBag:GetService(GameConfigDataService)
	dataService:SetConfigPicker(self._configPicker)

	self._serviceBag:GetService((require :: any)("GameConfigCommandService"))
end

function GameConfigService.Start(self: GameConfigService): ()
	const parent = self:GetPreferredParent()
	for _, child in parent:GetChildren() do
		if child:IsA("Folder") then
			self:RegisterConfigFolder(child)
		end
	end

	self._maid:GiveTask(parent.ChildAdded:Connect(function(child)
		if child:IsA("Folder") then
			self:RegisterConfigFolder(child)
		end
	end))
	self._maid:GiveTask(parent.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Folder") then
			self:_tryRegisterAssetFolder(descendant)
		end
	end))
end

--[=[
	Registers a manually-authored configuration Folder and every valid asset
	Folder already inside it. This is useful for configurations created in Studio
	or cloned from a template.

	@param config Folder
	@return Folder
]=]
function GameConfigService.RegisterConfigFolder(self: GameConfigService, config: Folder): Folder
	assert(typeof(config) == "Instance" and config:IsA("Folder"), "Bad config")

	if config:GetAttribute(GameConfigConstants.GAME_ID_ATTRIBUTE) == nil then
		config:SetAttribute(GameConfigConstants.GAME_ID_ATTRIBUTE, game.GameId)
	end
	assert(
		type(config:GetAttribute(GameConfigConstants.GAME_ID_ATTRIBUTE)) == "number",
		"Config GameId attribute must be a number"
	)

	if not self._binders.GameConfig:HasTag(config) then
		self._binders.GameConfig:Bind(config)
	end

	for _, descendant in config:GetDescendants() do
		if descendant:IsA("Folder") then
			self:_tryRegisterAssetFolder(descendant)
		end
	end
	return config
end

--[=[
	Creates a tagged configuration for a universe game ID.

	@param gameId number?
	@param configName string?
	@return Folder
]=]
function GameConfigService.CreateConfig(self: GameConfigService, gameId: number?, configName: string?): Folder
	const resolvedGameId = gameId or game.GameId
	assert(type(resolvedGameId) == "number" and resolvedGameId >= 0 and resolvedGameId % 1 == 0, "Bad gameId")
	assert(configName == nil or (type(configName) == "string" and configName ~= ""), "Bad configName")

	const config = GameConfigUtils.create(self._binders.GameConfig, resolvedGameId)
	config.Name = configName or `GameConfig_{resolvedGameId}`
	config.Parent = self:GetPreferredParent()
	return config
end

--[=[
	Adds or updates a badge in the default configuration.

	@param assetKey string
	@param badgeId number
	@return Folder
]=]
function GameConfigService.AddBadge(self: GameConfigService, assetKey: string, badgeId: number): Folder
	return self:AddTypedAsset(GameConfigAssetTypes.BADGE, assetKey, badgeId)
end

--[=[
	Adds or updates a developer product in the default configuration.

	@param assetKey string
	@param productId number
	@return Folder
]=]
function GameConfigService.AddProduct(self: GameConfigService, assetKey: string, productId: number): Folder
	return self:AddTypedAsset(GameConfigAssetTypes.PRODUCT, assetKey, productId)
end

--[=[
	Adds or updates a game pass in the default configuration.

	@param assetKey string
	@param passId number
	@return Folder
]=]
function GameConfigService.AddPass(self: GameConfigService, assetKey: string, passId: number): Folder
	return self:AddTypedAsset(GameConfigAssetTypes.PASS, assetKey, passId)
end

--[=[
	Adds or updates a place in the default configuration.

	@param assetKey string
	@param placeId number
	@return Folder
]=]
function GameConfigService.AddPlace(self: GameConfigService, assetKey: string, placeId: number): Folder
	return self:AddTypedAsset(GameConfigAssetTypes.PLACE, assetKey, placeId)
end

--[=[
	Adds or updates a catalog asset in the default configuration.

	@param assetKey string
	@param assetId number
	@return Folder
]=]
function GameConfigService.AddAsset(self: GameConfigService, assetKey: string, assetId: number): Folder
	return self:AddTypedAsset(GameConfigAssetTypes.ASSET, assetKey, assetId)
end

--[=[
	Adds or updates a bundle in the default configuration.

	@param assetKey string
	@param bundleId number
	@return Folder
]=]
function GameConfigService.AddBundle(self: GameConfigService, assetKey: string, bundleId: number): Folder
	return self:AddTypedAsset(GameConfigAssetTypes.BUNDLE, assetKey, bundleId)
end

--[=[
	Adds or updates a subscription in the default configuration.

	@param assetKey string
	@param subscriptionId string
	@return Folder
]=]
function GameConfigService.AddSubscription(self: GameConfigService, assetKey: string, subscriptionId: string): Folder
	return self:AddTypedAsset(GameConfigAssetTypes.SUBSCRIPTION, assetKey, subscriptionId)
end

--[=[
	Adds or updates a membership entry in the default configuration.

	@param assetKey string
	@param membershipId string
	@return Folder
]=]
function GameConfigService.AddMembership(self: GameConfigService, assetKey: string, membershipId: string): Folder
	return self:AddTypedAsset(GameConfigAssetTypes.MEMBERSHIP, assetKey, membershipId)
end

--[=[
	Adds or updates an asset of any supported type in the default configuration.

	@param assetType GameConfigAssetType
	@param assetKey string
	@param assetId GameConfigAssetId
	@return Folder
]=]
function GameConfigService.AddTypedAsset(
	self: GameConfigService,
	assetType: AssetType,
	assetKey: string,
	assetId: AssetId
): Folder
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetKey) == "string" and assetKey ~= "", "Bad assetKey")
	assert(GameConfigAssetUtils.isValidAssetId(assetType, assetId), "Bad assetId")

	const config = self:_getOrCreateDefaultGameConfig()
	const assetFolder = GameConfigUtils.getOrCreateAssetFolder(config, assetType)
	const existing = assetFolder:FindFirstChild(assetKey)
	if existing then
		assert(existing:IsA("Folder"), `{existing:GetFullName()} must be a Folder`)
		existing:SetAttribute(GameConfigAssetConstants.ASSET_TYPE_ATTRIBUTE, assetType)
		existing:SetAttribute(GameConfigAssetConstants.ASSET_ID_ATTRIBUTE, assetId)
		if not self._binders.GameConfigAsset:HasTag(existing) then
			self._binders.GameConfigAsset:Bind(existing)
		end
		return existing
	end

	const asset = GameConfigAssetUtils.create(self._binders.GameConfigAsset, assetType, assetKey, assetId)
	asset.Parent = assetFolder
	return asset
end

--[=[
	Removes every default-config asset matching a type and key.

	@param assetType GameConfigAssetType
	@param assetKey string
	@return boolean
]=]
function GameConfigService.RemoveTypedAsset(self: GameConfigService, assetType: AssetType, assetKey: string): boolean
	assert(GameConfigAssetTypeUtils.isAssetType(assetType), "Bad assetType")
	assert(type(assetKey) == "string" and assetKey ~= "", "Bad assetKey")

	const config = self:_findDefaultGameConfig()
	if not config then
		return false
	end

	const assetFolder = GameConfigUtils.getOrCreateAssetFolder(config, assetType)
	local removed = false
	for _, child in assetFolder:GetChildren() do
		if child.Name == assetKey then
			child:Destroy()
			removed = true
		end
	end
	return removed
end

--[=[
	Returns the server configuration picker.

	@return GameConfigPicker
]=]
function GameConfigService.GetConfigPicker(self: GameConfigService): GameConfigPicker.GameConfigPicker
	return self._configPicker
end

--[=[
	Returns the replicated container where configuration Folders should be parented.

	@return Instance
]=]
function GameConfigService.GetPreferredParent(self: GameConfigService): Instance
	return assert(self._getPreferredParent(), "Unable to create GameConfigs container")
end

function GameConfigService._findDefaultGameConfig(self: GameConfigService): Folder?
	for _, config in self._binders.GameConfig:GetAll() do
		if
			config:GetGameId() == game.GameId
			and config:GetConfigName() == GameConfigServiceConstants.DEFAULT_CONFIG_NAME
		then
			return config:GetFolder()
		end
	end

	for _, child in self:GetPreferredParent():GetChildren() do
		if
			child:IsA("Folder")
			and child.Name == GameConfigServiceConstants.DEFAULT_CONFIG_NAME
			and child:GetAttribute(GameConfigConstants.GAME_ID_ATTRIBUTE) == game.GameId
		then
			return self:RegisterConfigFolder(child)
		end
	end
	return nil
end

function GameConfigService._getOrCreateDefaultGameConfig(self: GameConfigService): Folder
	const existing = self:_findDefaultGameConfig()
	if existing then
		return existing
	end

	return self:CreateConfig(game.GameId, GameConfigServiceConstants.DEFAULT_CONFIG_NAME)
end

function GameConfigService._tryRegisterAssetFolder(self: GameConfigService, asset: Folder): ()
	const typeFolder = asset.Parent
	const config = typeFolder and typeFolder.Parent
	if not typeFolder or not config or not typeFolder:IsA("Folder") or not config:IsA("Folder") then
		return
	end
	if not self._binders.GameConfig:HasTag(config) then
		return
	end

	for _, assetType in GameConfigAssetTypes:GetValues() do
		if typeFolder.Name == GameConfigAssetTypeUtils.getPlural(assetType) then
			const assetId = asset:GetAttribute(GameConfigAssetConstants.ASSET_ID_ATTRIBUTE)
			if not GameConfigAssetUtils.isValidAssetId(assetType, assetId) then
				return
			end

			asset:SetAttribute(GameConfigAssetConstants.ASSET_TYPE_ATTRIBUTE, assetType)
			if not self._binders.GameConfigAsset:HasTag(asset) then
				self._binders.GameConfigAsset:Bind(asset)
			end
			return
		end
	end
end

function GameConfigService.Destroy(self: GameConfigService): ()
	self._maid:Destroy()
end

return GameConfigService
