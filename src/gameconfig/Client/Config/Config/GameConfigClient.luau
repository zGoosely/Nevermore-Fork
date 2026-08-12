--!strict
--[=[
	Client model for a replicated game configuration.

	@class GameConfigClient
	@client
]=]

const require = require("../../../../Loader").load()

const GameConfigBase = require("GameConfigBase")
const GameConfigBindersClient = require("GameConfigBindersClient")
const ServiceBag = require("ServiceBag")

const GameConfigClient = setmetatable({}, GameConfigBase)
GameConfigClient.ClassName = "GameConfigClient"
GameConfigClient.__index = GameConfigClient

export type GameConfigClient =
	typeof(setmetatable(
		{} :: {
			_serviceBag: ServiceBag.ServiceBag,
			_gameConfigBindersClient: any,
		},
		{} :: typeof({ __index = GameConfigClient })
	))
	& GameConfigBase.GameConfigBase

--[=[
	Constructs the client configuration model. Called automatically by the client
	binder.

	@param folder Folder
	@param serviceBag ServiceBag
	@return GameConfigClient
]=]
function GameConfigClient.new(folder: Folder, serviceBag: ServiceBag.ServiceBag): GameConfigClient
	const self = setmetatable(GameConfigBase.new(folder) :: any, GameConfigClient) :: GameConfigClient
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._gameConfigBindersClient = self._serviceBag:GetService(GameConfigBindersClient)
	self:InitObservation()
	return self
end

function GameConfigClient.GetGameConfigAssetBinder(self: GameConfigClient): any
	return self._gameConfigBindersClient.GameConfigAsset
end

return GameConfigClient
