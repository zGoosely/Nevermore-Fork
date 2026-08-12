--!strict
--[=[
	Server model for a replicated game configuration.

	@class GameConfig
	@server
]=]

const require = require("../../../../Loader").load()

const GameConfigAssetTypes = require("GameConfigAssetTypes")
const GameConfigBase = require("GameConfigBase")
const GameConfigBindersServer = require("GameConfigBindersServer")
const GameConfigUtils = require("GameConfigUtils")
const ServiceBag = require("ServiceBag")

const GameConfig = setmetatable({}, GameConfigBase)
GameConfig.ClassName = "GameConfig"
GameConfig.__index = GameConfig

export type GameConfig =
	typeof(setmetatable(
		{} :: {
			_serviceBag: ServiceBag.ServiceBag,
			_gameConfigBindersServer: any,
		},
		{} :: typeof({ __index = GameConfig })
	))
	& GameConfigBase.GameConfigBase

--[=[
	Constructs the server configuration model. Called automatically by the server
	binder.

	@param folder Folder
	@param serviceBag ServiceBag
	@return GameConfig
]=]
function GameConfig.new(folder: Folder, serviceBag: ServiceBag.ServiceBag): GameConfig
	const self = setmetatable(GameConfigBase.new(folder) :: any, GameConfig) :: GameConfig
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._gameConfigBindersServer = self._serviceBag:GetService(GameConfigBindersServer)

	for _, assetType in GameConfigAssetTypes:GetValues() do
		GameConfigUtils.getOrCreateAssetFolder(folder, assetType)
	end

	self:InitObservation()
	return self
end

function GameConfig.GetGameConfigAssetBinder(self: GameConfig): any
	return self._gameConfigBindersServer.GameConfigAsset
end

return GameConfig
