--!strict
--[=[
	Server-side tracker for team kills.

	@class TeamKillTracker
]=]

const require = require("../../../Loader").load()

const BaseObject = require("BaseObject")
const DeathReportService = require("DeathReportService")
const DeathReportUtils = require("DeathReportUtils")
const ServiceBag = require("ServiceBag")
const t = require("t")

const TeamKillTracker = setmetatable({}, BaseObject)
TeamKillTracker.ClassName = "TeamKillTracker"
TeamKillTracker.__index = TeamKillTracker

export type TeamKillTracker =
	typeof(setmetatable(
		{} :: {
			_obj: IntValue,
			_serviceBag: ServiceBag.ServiceBag,
			_deathReportService: DeathReportService.DeathReportService,
			_team: Team,
		},
		{} :: typeof({ __index = TeamKillTracker })
	))
	& BaseObject.BaseObject

function TeamKillTracker.new(scoreObject: IntValue, serviceBag: ServiceBag.ServiceBag): TeamKillTracker
	assert(t.instanceIsA("IntValue")(scoreObject), "Bad scoreObject")
	assert(t.table(serviceBag), "Bad serviceBag")

	const self: TeamKillTracker = setmetatable(BaseObject.new(scoreObject) :: any, TeamKillTracker)

	self._serviceBag = serviceBag
	self._deathReportService = self._serviceBag:GetService(DeathReportService)

	const team = (self._obj :: IntValue).Parent
	assert(t.instanceIsA("Team")(team), "Bad team")
	self._team = team

	self._maid:GiveTask(self._deathReportService.NewDeathReport:Connect(function(deathReport)
		self:_handleDeathReport(deathReport)
	end))

	return self
end

function TeamKillTracker.GetTeam(self: TeamKillTracker): Instance?
	return (self._obj :: IntValue).Parent
end

function TeamKillTracker.GetKills(self: TeamKillTracker): number
	return (self._obj :: IntValue).Value
end

function TeamKillTracker._handleDeathReport(self: TeamKillTracker, deathReport: DeathReportUtils.DeathReport): ()
	if deathReport.killerPlayer then
		if deathReport.killerPlayer.Team == self._team then
			const obj = self._obj :: IntValue
			obj.Value += 1
		end
	end
end

function TeamKillTracker.Destroy(self: TeamKillTracker): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return TeamKillTracker
