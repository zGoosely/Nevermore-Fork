--!strict
--[=[
	Server-side tracker for player deaths.

	@class PlayerDeathTracker
]=]

const require = require("../../../Loader").load()

const BaseObject = require("BaseObject")
const DeathReportService = require("DeathReportService")
const ServiceBag = require("ServiceBag")
const t = require("t")

const PlayerDeathTracker = setmetatable({}, BaseObject)
PlayerDeathTracker.ClassName = "PlayerDeathTracker"
PlayerDeathTracker.__index = PlayerDeathTracker

export type PlayerDeathTracker =
	typeof(setmetatable(
		{} :: {
			_obj: IntValue,
			_serviceBag: ServiceBag.ServiceBag,
			_deathReportService: DeathReportService.DeathReportService,
			_player: Player,
		},
		{} :: typeof({ __index = PlayerDeathTracker })
	))
	& BaseObject.BaseObject

function PlayerDeathTracker.new(scoreObject: IntValue, serviceBag: ServiceBag.ServiceBag): PlayerDeathTracker
	assert(t.instanceIsA("IntValue")(scoreObject), "Bad scoreObject")
	assert(t.table(serviceBag), "Bad serviceBag")

	const self: PlayerDeathTracker = setmetatable(BaseObject.new(scoreObject) :: any, PlayerDeathTracker)

	self._serviceBag = serviceBag
	self._deathReportService = self._serviceBag:GetService(DeathReportService)

	const player = self._obj.Parent
	assert(t.instanceIsA("Player")(player), "Bad player")
	self._player = player

	self._maid:GiveTask(self._deathReportService:ObservePlayerDeathReports(self._player):Subscribe(function(deathReport)
		assert(deathReport.player == self._player, "Bad player")
		self._obj.Value += 1
	end))

	return self
end

function PlayerDeathTracker.Destroy(self: PlayerDeathTracker): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return PlayerDeathTracker
