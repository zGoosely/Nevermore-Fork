--!strict
--[=[
	Client-side tracker for player deaths.

	@class PlayerDeathTrackerClient
]=]

const require = require("../../../Loader").load()

const BaseObject = require("BaseObject")
const ServiceBag = require("ServiceBag")
const t = require("t")

const PlayerDeathTrackerClient = setmetatable({}, BaseObject)
PlayerDeathTrackerClient.ClassName = "PlayerDeathTrackerClient"
PlayerDeathTrackerClient.__index = PlayerDeathTrackerClient

export type PlayerDeathTrackerClient =
	typeof(setmetatable(
		{} :: {
			_obj: IntValue,
			_serviceBag: ServiceBag.ServiceBag,
			DeathsChanged: RBXScriptSignal,
		},
		{} :: typeof({ __index = PlayerDeathTrackerClient })
	))
	& BaseObject.BaseObject

function PlayerDeathTrackerClient.new(tracker: IntValue, serviceBag: ServiceBag.ServiceBag): PlayerDeathTrackerClient
	assert(t.instanceIsA("IntValue")(tracker), "Bad tracker")
	assert(t.table(serviceBag), "Bad serviceBag")

	const self: PlayerDeathTrackerClient = setmetatable(BaseObject.new(tracker) :: any, PlayerDeathTrackerClient)

	self._serviceBag = serviceBag
	self.DeathsChanged = (self._obj :: IntValue).Changed

	return self
end

function PlayerDeathTrackerClient.GetDeathValue(self: PlayerDeathTrackerClient): IntValue
	return self._obj :: IntValue
end

function PlayerDeathTrackerClient.GetPlayer(self: PlayerDeathTrackerClient): Instance?
	return (self._obj :: IntValue).Parent
end

function PlayerDeathTrackerClient.GetKills(self: PlayerDeathTrackerClient): number
	return (self._obj :: IntValue).Value
end

function PlayerDeathTrackerClient.Destroy(self: PlayerDeathTrackerClient): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return PlayerDeathTrackerClient
