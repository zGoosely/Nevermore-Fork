--!strict
--[=[
	Handles shared observable subscription tables for the client and server.

	@class DeathReportProcessor
]=]

const Players = game:GetService("Players")

const require = require("../../Loader").load()

const BaseObject = require("BaseObject")
const DeathReportUtils = require("DeathReportUtils")
const Observable = require("Observable")
const ObservableSubscriptionTable = require("ObservableSubscriptionTable")
const t = require("t")

const DeathReportProcessor = setmetatable({}, BaseObject)
DeathReportProcessor.ClassName = "DeathReportProcessor"
DeathReportProcessor.__index = DeathReportProcessor

export type DeathReportProcessor =
	typeof(setmetatable(
		{} :: {
			_playerKillerSubTable: ObservableSubscriptionTable.ObservableSubscriptionTable<
				DeathReportUtils.DeathReport
			>,
			_playerDeathSubTable: ObservableSubscriptionTable.ObservableSubscriptionTable<DeathReportUtils.DeathReport>,
			_humanoidKillerSubTable: ObservableSubscriptionTable.ObservableSubscriptionTable<
				DeathReportUtils.DeathReport
			>,
			_humanoidDeathSubTable: ObservableSubscriptionTable.ObservableSubscriptionTable<
				DeathReportUtils.DeathReport
			>,
			_characterKillerSubTable: ObservableSubscriptionTable.ObservableSubscriptionTable<
				DeathReportUtils.DeathReport
			>,
			_characterDeathSubTable: ObservableSubscriptionTable.ObservableSubscriptionTable<
				DeathReportUtils.DeathReport
			>,
		},
		{} :: typeof({ __index = DeathReportProcessor })
	))
	& BaseObject.BaseObject

function DeathReportProcessor.new(): DeathReportProcessor
	const self = setmetatable(BaseObject.new() :: any, DeathReportProcessor)

	self._playerKillerSubTable = self._maid:Add(ObservableSubscriptionTable.new())
	self._playerDeathSubTable = self._maid:Add(ObservableSubscriptionTable.new())
	self._humanoidKillerSubTable = self._maid:Add(ObservableSubscriptionTable.new())
	self._humanoidDeathSubTable = self._maid:Add(ObservableSubscriptionTable.new())
	self._characterKillerSubTable = self._maid:Add(ObservableSubscriptionTable.new())
	self._characterDeathSubTable = self._maid:Add(ObservableSubscriptionTable.new())

	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self._playerKillerSubTable:Complete(player)
		self._playerDeathSubTable:Complete(player)
	end))

	return self
end

--[=[
	Observes killer reports for the given player.

	@within DeathReportProcessor
	@param player Player
	@return Observable<DeathReport>
]=]
function DeathReportProcessor.ObservePlayerKillerReports(
	self: DeathReportProcessor,
	player: Player
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Player")(player), "Bad player")

	return self._playerKillerSubTable:Observe(player)
end

--[=[
	Observes death reports for the given player.

	@within DeathReportProcessor
	@param player Player
	@return Observable<DeathReport>
]=]
function DeathReportProcessor.ObservePlayerDeathReports(
	self: DeathReportProcessor,
	player: Player
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Player")(player), "Bad player")

	return self._playerDeathSubTable:Observe(player)
end

--[=[
	Observes death reports for the given humanoid.

	@within DeathReportProcessor
	@param humanoid Humanoid
	@return Observable<DeathReport>
]=]
function DeathReportProcessor.ObserveHumanoidDeathReports(
	self: DeathReportProcessor,
	humanoid: Humanoid
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")

	return self._humanoidDeathSubTable:Observe(humanoid)
end

--[=[
	Observes killer reports for the given humanoid.

	@within DeathReportProcessor
	@param humanoid Humanoid
	@return Observable<DeathReport>
]=]
function DeathReportProcessor.ObserveHumanoidKillerReports(
	self: DeathReportProcessor,
	humanoid: Humanoid
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")

	return self._humanoidKillerSubTable:Observe(humanoid)
end

--[=[
	Observes killer reports for the given character.

	@within DeathReportProcessor
	@param character Model
	@return Observable<DeathReport>
]=]
function DeathReportProcessor.ObserveCharacterKillerReports(
	self: DeathReportProcessor,
	character: Model
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Model")(character), "Bad character")

	return self._characterKillerSubTable:Observe(character)
end

--[=[
	Observes death reports for the given character.

	@within DeathReportProcessor
	@param character Model
	@return Observable<DeathReport>
]=]
function DeathReportProcessor.ObserveCharacterDeathReports(
	self: DeathReportProcessor,
	character: Model
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Model")(character), "Bad character")

	return self._characterDeathSubTable:Observe(character)
end

--[=[
	Handles a death report by dispatching to internal subscription tables.

	@within DeathReportProcessor
	@param deathReport DeathReport
]=]
function DeathReportProcessor.HandleDeathReport(
	self: DeathReportProcessor,
	deathReport: DeathReportUtils.DeathReport
): ()
	assert(DeathReportUtils.isDeathReport(deathReport), "Bad deathReport")

	if deathReport.killerPlayer then
		self._playerKillerSubTable:Fire(deathReport.killerPlayer, deathReport)
	end

	if deathReport.killerHumanoid then
		self._humanoidKillerSubTable:Fire(deathReport.killerHumanoid, deathReport)

		const character = deathReport.killerHumanoid.Parent
		if character and character:IsA("Model") then
			self._characterKillerSubTable:Fire(character, deathReport)
		end
	end

	if deathReport.player then
		self._playerDeathSubTable:Fire(deathReport.player, deathReport)
	end

	if deathReport.humanoid then
		self._humanoidDeathSubTable:Fire(deathReport.humanoid, deathReport)

		const character = deathReport.humanoid.Parent
		if character and character:IsA("Model") then
			self._characterDeathSubTable:Fire(character, deathReport)
		end
	end
end

function DeathReportProcessor.Destroy(self: DeathReportProcessor): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return DeathReportProcessor
