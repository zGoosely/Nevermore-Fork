--!strict
--[=[
	Client-side tracker for team kills.

	@class TeamKillTrackerClient
]=]

const require = require("../../../Loader").load()

const BaseObject = require("BaseObject")
const ServiceBag = require("ServiceBag")
const t = require("t")

const TeamKillTrackerClient = setmetatable({}, BaseObject)
TeamKillTrackerClient.ClassName = "TeamKillTrackerClient"
TeamKillTrackerClient.__index = TeamKillTrackerClient

export type TeamKillTrackerClient =
	typeof(setmetatable(
		{} :: {
			_obj: IntValue,
			_serviceBag: ServiceBag.ServiceBag,
			KillsChanged: RBXScriptSignal,
		},
		{} :: typeof({ __index = TeamKillTrackerClient })
	))
	& BaseObject.BaseObject

function TeamKillTrackerClient.new(tracker: IntValue, serviceBag: ServiceBag.ServiceBag): TeamKillTrackerClient
	assert(t.instanceIsA("IntValue")(tracker), "Bad tracker")
	assert(t.table(serviceBag), "Bad serviceBag")

	const self: TeamKillTrackerClient = setmetatable(BaseObject.new(tracker) :: any, TeamKillTrackerClient)

	self._serviceBag = serviceBag
	self.KillsChanged = self._obj.Changed

	return self
end

function TeamKillTrackerClient.GetKillValue(self: TeamKillTrackerClient): IntValue
	return self._obj
end

function TeamKillTrackerClient.GetTeam(self: TeamKillTrackerClient): Instance?
	return self._obj.Parent
end

function TeamKillTrackerClient.GetKills(self: TeamKillTrackerClient): number
	return self._obj.Value
end

function TeamKillTrackerClient.Destroy(self: TeamKillTrackerClient): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return TeamKillTrackerClient
