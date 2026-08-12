--!strict
--[=[
	Small shared dependency that exposes the realm's active GameConfigPicker to
	packages which should not depend directly on the server or client service.

	@class GameConfigDataService
]=]

const require = require("../../Loader").load()

const GameConfigPicker = require("GameConfigPicker")
const ServiceBag = require("ServiceBag")

const GameConfigDataService = {}
GameConfigDataService.ServiceName = "GameConfigDataService"

export type GameConfigDataService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_configPicker: GameConfigPicker.GameConfigPicker?,
	},
	{} :: typeof({ __index = GameConfigDataService })
))

function GameConfigDataService.Init(self: GameConfigDataService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._configPicker = nil
end

--[=[
	Assigns the picker for the current realm.

	@param configPicker GameConfigPicker
]=]
function GameConfigDataService.SetConfigPicker(
	self: GameConfigDataService,
	configPicker: GameConfigPicker.GameConfigPicker
): ()
	assert(configPicker, "Bad configPicker")
	assert(not self._configPicker or self._configPicker == configPicker, "Config picker already assigned")
	self._configPicker = configPicker
end

--[=[
	Returns the picker for the current realm.

	@return GameConfigPicker
]=]
function GameConfigDataService.GetConfigPicker(self: GameConfigDataService): GameConfigPicker.GameConfigPicker
	return assert(self._configPicker, "GameConfigService has not assigned a config picker yet")
end

return GameConfigDataService
