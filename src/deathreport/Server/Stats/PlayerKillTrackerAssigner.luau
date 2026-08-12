--!strict
--[=[
	Assigns player kill and death trackers to connecting players.

	@class PlayerKillTrackerAssigner
]=]

const Players = game:GetService("Players")

const require = require("../../../Loader").load()

const BaseObject = require("BaseObject")
const DeathReportBindersServer = require("DeathReportBindersServer")
const Maid = require("Maid")
const PlayerKillTrackerUtils = require("PlayerKillTrackerUtils")
const ServiceBag = require("ServiceBag")
const t = require("t")

const PlayerKillTrackerAssigner = setmetatable({}, BaseObject)
PlayerKillTrackerAssigner.ClassName = "PlayerKillTrackerAssigner"
PlayerKillTrackerAssigner.__index = PlayerKillTrackerAssigner

export type PlayerKillTrackerAssigner =
	typeof(setmetatable(
		{} :: {
			_serviceBag: ServiceBag.ServiceBag,
			_deathReportBindersServer: any,
			_killTrackers: { [Player]: Instance },
		},
		{} :: typeof({ __index = PlayerKillTrackerAssigner })
	))
	& BaseObject.BaseObject

function PlayerKillTrackerAssigner.new(serviceBag: ServiceBag.ServiceBag): PlayerKillTrackerAssigner
	assert(t.table(serviceBag), "Bad serviceBag")

	const self: PlayerKillTrackerAssigner = setmetatable(BaseObject.new() :: any, PlayerKillTrackerAssigner)

	self._serviceBag = serviceBag
	self._deathReportBindersServer = self._serviceBag:GetService(DeathReportBindersServer)
	self._killTrackers = {}

	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player)
		self:_handlePlayerAdded(player)
	end))
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self:_handlePlayerRemoving(player)
	end))

	for _, player in Players:GetPlayers() do
		self:_handlePlayerAdded(player)
	end

	return self
end

function PlayerKillTrackerAssigner.GetPlayerKills(self: PlayerKillTrackerAssigner, player: Player): number?
	assert(t.instanceIsA("Player")(player), "Bad player")

	const tracker = self:GetPlayerKillTracker(player)
	if tracker then
		return tracker:GetKills()
	else
		return nil
	end
end

function PlayerKillTrackerAssigner.GetPlayerKillTracker(self: PlayerKillTrackerAssigner, player: Player): any
	assert(t.instanceIsA("Player")(player), "Bad player")

	const trackerInstance = self._killTrackers[player]
	if trackerInstance then
		return self._deathReportBindersServer.PlayerKillTracker:Get(trackerInstance)
	else
		return nil
	end
end

function PlayerKillTrackerAssigner._handlePlayerRemoving(self: PlayerKillTrackerAssigner, player: Player): ()
	self._maid[player] = nil
end

function PlayerKillTrackerAssigner._handlePlayerAdded(self: PlayerKillTrackerAssigner, player: Player): ()
	const maid = Maid.new()

	const killTracker = PlayerKillTrackerUtils.create(self._deathReportBindersServer.PlayerKillTracker, player)
	maid:GiveTask(killTracker)

	self._killTrackers[player] = killTracker

	maid:GiveTask(function()
		self._killTrackers[player] = nil
	end)

	const deathTracker = PlayerKillTrackerUtils.create(self._deathReportBindersServer.PlayerDeathTracker, player)
	maid:GiveTask(deathTracker)

	self._maid[player] = maid
end

function PlayerKillTrackerAssigner.Destroy(self: PlayerKillTrackerAssigner): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return PlayerKillTrackerAssigner
