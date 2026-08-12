--!strict
--[=[
	Server-side tracker for player kills.

	@class PlayerKillTracker
]=]

const require = require("../../../Loader").load()

const BaseObject = require("BaseObject")
const DeathReportService = require("DeathReportService")
const ServiceBag = require("ServiceBag")
const t = require("t")

const PlayerKillTracker = setmetatable({}, BaseObject)
PlayerKillTracker.ClassName = "PlayerKillTracker"
PlayerKillTracker.__index = PlayerKillTracker

export type PlayerKillTracker =
	typeof(setmetatable(
		{} :: {
			_obj: IntValue,
			_serviceBag: ServiceBag.ServiceBag,
			_deathReportService: DeathReportService.DeathReportService,
			_player: Player,
		},
		{} :: typeof({ __index = PlayerKillTracker })
	))
	& BaseObject.BaseObject

function PlayerKillTracker.new(scoreObject: IntValue, serviceBag: ServiceBag.ServiceBag): PlayerKillTracker
	assert(t.instanceIsA("IntValue")(scoreObject), "Bad scoreObject")
	assert(t.table(serviceBag), "Bad serviceBag")

	const self: PlayerKillTracker = setmetatable(BaseObject.new(scoreObject) :: any, PlayerKillTracker)

	self._serviceBag = serviceBag
	self._deathReportService = self._serviceBag:GetService(DeathReportService)

	const player = self._obj.Parent
	assert(t.instanceIsA("Player")(player), "Bad player")
	self._player = player

	self._maid:GiveTask(
		self._deathReportService:ObservePlayerKillerReports(self._player):Subscribe(function(deathReport)
			assert(deathReport.killerPlayer == self._player, "Bad player")
			self._obj.Value += 1
		end)
	)

	return self
end

function PlayerKillTracker.GetKillValue(self: PlayerKillTracker): IntValue
	return self._obj
end

function PlayerKillTracker.GetPlayer(self: PlayerKillTracker): Player
	return self._player
end

function PlayerKillTracker.GetKills(self: PlayerKillTracker): number
	return self._obj.Value
end

function PlayerKillTracker.Destroy(self: PlayerKillTracker): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return PlayerKillTracker
