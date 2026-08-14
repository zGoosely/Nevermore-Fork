--!strict
--[=[
	Registers client Cmdr game-config argument types and displays the active config
	name in Cmdr.

	@class GameConfigCommandServiceClient
	@client
]=]
const CmdrServiceClient = require("@game/ReplicatedStorage/Packages/CmdrServiceClient")
const GameConfigCmdrUtils = require("../../Shared/Cmdr/GameConfigCmdrUtils")
const GameConfigServiceClient = require("../GameConfigServiceClient")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Rx = require("@game/ReplicatedStorage/Packages/Rx")
const RxStateStackUtils = require("@game/ReplicatedStorage/Packages/RxStateStackUtils")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

const GameConfigCommandServiceClient = {}
GameConfigCommandServiceClient.ServiceName = "GameConfigCommandServiceClient"

export type GameConfigCommandServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_cmdrService: CmdrServiceClient.CmdrServiceClient,
		_gameConfigServiceClient: GameConfigServiceClient.GameConfigServiceClient,
	},
	{} :: typeof({ __index = GameConfigCommandServiceClient })
))

function GameConfigCommandServiceClient.Init(
	self: GameConfigCommandServiceClient,
	serviceBag: ServiceBag.ServiceBag
): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._cmdrService = self._serviceBag:GetService(CmdrServiceClient)
	self._gameConfigServiceClient = self._serviceBag:GetService(GameConfigServiceClient)
end

function GameConfigCommandServiceClient.Start(self: GameConfigCommandServiceClient): ()
	const picker = self._gameConfigServiceClient:GetConfigPicker()
	self._maid:GivePromise(self._cmdrService:PromiseCmdr()):Then(function(cmdr)
		GameConfigCmdrUtils.registerAssetTypes(cmdr, picker)

		const activeConfig = self._maid:Add(RxStateStackUtils.createStateStack(picker:ObserveActiveConfigsBrio()))
		self._maid:GiveTask(activeConfig
			:Observe()
			:Pipe({
				Rx.switchMap(function(config): any
					return if config then config:ObserveConfigName() else Rx.of(nil)
				end),
			})
			:Subscribe(function(configName)
				cmdr:SetPlaceName(configName or "Cmdr")
			end))
	end)
end

function GameConfigCommandServiceClient.Destroy(self: GameConfigCommandServiceClient): ()
	self._maid:Destroy()
end

return GameConfigCommandServiceClient
