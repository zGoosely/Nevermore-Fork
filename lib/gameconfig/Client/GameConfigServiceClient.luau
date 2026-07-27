--!strict
--[=[
	Provides client-side reactive access to replicated game configurations.

	@class GameConfigServiceClient
	@client
]=]

const require = require("../../Loader").load()

const GameConfigDataService = require("GameConfigDataService")
const GameConfigPicker = require("GameConfigPicker")
const GameConfigTranslator = require("GameConfigTranslator")
const Maid = require("Maid")
const MarketplaceServiceCache = require("MarketplaceServiceCache")
const ServiceBag = require("ServiceBag")

const GameConfigServiceClient = {}
GameConfigServiceClient.ServiceName = "GameConfigServiceClient"

export type GameConfigServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_binders: any,
		_configPicker: GameConfigPicker.GameConfigPicker,
	},
	{} :: typeof({ __index = GameConfigServiceClient })
))

function GameConfigServiceClient.Init(self: GameConfigServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	self._serviceBag:GetService(MarketplaceServiceCache)
	self._serviceBag:GetService(GameConfigTranslator)
	self._binders = self._serviceBag:GetService(require("GameConfigBindersClient"))
	self._configPicker =
		self._maid:Add(GameConfigPicker.new(self._serviceBag, self._binders.GameConfig, self._binders.GameConfigAsset))

	const dataService = self._serviceBag:GetService(GameConfigDataService)
	dataService:SetConfigPicker(self._configPicker)
	self._serviceBag:GetService((require :: any)("GameConfigCommandServiceClient"))
end

function GameConfigServiceClient.Start(_self: GameConfigServiceClient): () end

--[=[
	Returns the client configuration picker.

	@return GameConfigPicker
]=]
function GameConfigServiceClient.GetConfigPicker(self: GameConfigServiceClient): GameConfigPicker.GameConfigPicker
	return self._configPicker
end

function GameConfigServiceClient.Destroy(self: GameConfigServiceClient): ()
	self._maid:Destroy()
end

return GameConfigServiceClient
