--!strict
--[=[
	Loads Roblox asset IDs from Mantle-generated configuration ModuleScripts and
	turns them into replicated GameConfig folders.

	@class MantleConfigProvider
	@server
]=]

const require = require("../../../Loader").load()

const GameConfigAssetTypes = require("GameConfigAssetTypes")
const GameConfigAssetUtils = require("GameConfigAssetUtils")
const GameConfigBindersServer = require("GameConfigBindersServer")
const GameConfigService = require("GameConfigService")
const GameConfigUtils = require("GameConfigUtils")
const Maid = require("Maid")
const ServiceBag = require("ServiceBag")
const StringUtils = require("StringUtils")

const MantleConfigProvider = {}
MantleConfigProvider.ClassName = "MantleConfigProvider"
MantleConfigProvider.__index = MantleConfigProvider

export type MantleConfigProvider = typeof(setmetatable(
	{} :: {
		_container: Instance,
		_serviceBag: ServiceBag.ServiceBag,
		_gameConfigService: GameConfigService.GameConfigService,
		_gameConfigBindersServer: any,
		_maid: Maid.Maid,
	},
	{} :: typeof({ __index = MantleConfigProvider })
))

--[=[
	Constructs a provider which loads every ModuleScript directly beneath the
	container during ServiceBag initialization.

	@param container Instance
	@return MantleConfigProvider
]=]
function MantleConfigProvider.new(container: Instance): MantleConfigProvider
	assert(typeof(container) == "Instance", "Bad container")
	return setmetatable({
		_container = container,
	}, MantleConfigProvider) :: any
end

function MantleConfigProvider.Init(self: MantleConfigProvider, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._gameConfigService = self._serviceBag:GetService(GameConfigService)
	self._gameConfigBindersServer = self._serviceBag:GetService(GameConfigBindersServer)

	for _, child in self._container:GetChildren() do
		if child:IsA("ModuleScript") then
			self:_loadConfig(child)
		end
	end
end

--[=[
	Loads one already-required Mantle output table. This is also useful when a
	build system provides Mantle data without a ModuleScript container.

	@param mantleConfigData table
	@param configName string
	@return Folder
]=]
function MantleConfigProvider.LoadConfigData(
	self: MantleConfigProvider,
	mantleConfigData: { [string]: any },
	configName: string
): Folder
	assert(type(mantleConfigData) == "table", "Bad mantleConfigData")
	assert(type(configName) == "string" and configName ~= "", "Bad configName")
	return self:_parseDataToConfig(mantleConfigData, configName)
end

function MantleConfigProvider._loadConfig(self: MantleConfigProvider, moduleScript: ModuleScript): ()
	const success, result = (pcall :: any)(require, moduleScript)
	assert(success, `Failed to load Mantle config {moduleScript:GetFullName()}: {tostring(result)}`)
	assert(type(result) == "table", `Mantle config {moduleScript:GetFullName()} must return a table`)
	self:_parseDataToConfig(result, moduleScript.Name)
end

function MantleConfigProvider._parseDataToConfig(
	self: MantleConfigProvider,
	mantleConfigData: { [string]: any },
	configName: string
): Folder
	const experienceSingleton = mantleConfigData.experience_singleton
	const experience = type(experienceSingleton) == "table" and experienceSingleton.experience or nil
	const gameId = type(experience) == "table" and experience.assetId or nil
	assert(type(gameId) == "number", "Mantle config has no experience_singleton.experience.assetId")

	const config = GameConfigUtils.create(self._gameConfigBindersServer.GameConfig, gameId)
	config.Name = configName

	const mantleTypes = {
		badge = GameConfigAssetTypes.BADGE,
		pass = GameConfigAssetTypes.PASS,
		product = GameConfigAssetTypes.PRODUCT,
		place = GameConfigAssetTypes.PLACE,
		asset = GameConfigAssetTypes.ASSET,
		bundle = GameConfigAssetTypes.BUNDLE,
	}

	for key, entry in mantleConfigData do
		if type(key) == "string" and type(entry) == "table" then
			for mantleType, assetType in mantleTypes do
				const data = entry[mantleType]
				const prefix = `{mantleType}_`
				if type(data) == "table" and StringUtils.startsWith(key, prefix) then
					const assetId = data.assetId
					if GameConfigAssetUtils.isValidAssetId(assetType, assetId) then
						const assetName = StringUtils.removePrefix(key, prefix)
						const asset = GameConfigAssetUtils.create(
							self._gameConfigBindersServer.GameConfigAsset,
							assetType,
							assetName,
							assetId
						)
						asset.Parent = GameConfigUtils.getOrCreateAssetFolder(config, assetType)
					end
				end
			end
		end
	end

	config.Parent = self._gameConfigService:GetPreferredParent()
	self._maid:GiveTask(config)
	return config
end

function MantleConfigProvider.Destroy(self: MantleConfigProvider): ()
	self._maid:Destroy()
end

return MantleConfigProvider
