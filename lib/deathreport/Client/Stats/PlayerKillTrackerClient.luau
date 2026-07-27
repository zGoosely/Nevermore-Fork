--!strict
--[=[
	Client-side tracker for player kills.

	@class PlayerKillTrackerClient
]=]

const require = require("../../../Loader").load()

const BaseObject = require("BaseObject")
const ServiceBag = require("ServiceBag")
const t = require("t")

const PlayerKillTrackerClient = setmetatable({}, BaseObject)
PlayerKillTrackerClient.ClassName = "PlayerKillTrackerClient"
PlayerKillTrackerClient.__index = PlayerKillTrackerClient

export type PlayerKillTrackerClient =
	typeof(setmetatable(
		{} :: {
			_obj: IntValue,
			_serviceBag: ServiceBag.ServiceBag,
			KillsChanged: RBXScriptSignal,
		},
		{} :: typeof({ __index = PlayerKillTrackerClient })
	))
	& BaseObject.BaseObject

function PlayerKillTrackerClient.new(tracker: IntValue, serviceBag: ServiceBag.ServiceBag): PlayerKillTrackerClient
	assert(t.instanceIsA("IntValue")(tracker), "Bad tracker")
	assert(t.table(serviceBag), "Bad serviceBag")

	const self: PlayerKillTrackerClient = setmetatable(BaseObject.new(tracker) :: any, PlayerKillTrackerClient)

	self._serviceBag = serviceBag
	self.KillsChanged = self._obj.Changed

	return self
end

function PlayerKillTrackerClient.GetKillValue(self: PlayerKillTrackerClient): IntValue
	return self._obj
end

function PlayerKillTrackerClient.GetPlayer(self: PlayerKillTrackerClient): Instance?
	return self._obj.Parent
end

function PlayerKillTrackerClient.GetKills(self: PlayerKillTrackerClient): number
	return self._obj.Value
end

function PlayerKillTrackerClient.Destroy(self: PlayerKillTrackerClient): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return PlayerKillTrackerClient
