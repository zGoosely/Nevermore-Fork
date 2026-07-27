--!strict
--[=[
	Centralized death reporting service which can be used to track deaths on the client.

	@class DeathReportServiceClient
	@client
]=]

const require = require("../Loader").load()

const DeathReportBindersClient = require("DeathReportBindersClient")
const DeathReportNetwork = require("DeathReportNetwork")
const DeathReportProcessor = require("DeathReportProcessor")
const DeathReportUtils = require("DeathReportUtils")
const Maid = require("Maid")
const Observable = require("Observable")
const PlayerIdServiceClient = require("PlayerIdServiceClient")
const PlayerIdServiceUtils = require("PlayerIdServiceUtils")
const ServiceBag = require("ServiceBag")
const Signal = require("Signal")
const t = require("t")

const MAX_DEATH_REPORTS = 5

const DeathReportServiceClient = {}
DeathReportServiceClient.ServiceName = "DeathReportServiceClient"

export type DeathReportServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		NewDeathReport: Signal.Signal<DeathReportUtils.DeathReport>,
		_playerIdServiceClient: PlayerIdServiceClient.PlayerIdServiceClient,
		_reportProcessor: DeathReportProcessor.DeathReportProcessor,
		_lastDeathReports: { DeathReportUtils.DeathReport },
	},
	{} :: typeof({ __index = DeathReportServiceClient })
))

--[=[
	Initializes DeathReportServiceClient for the given service bag.

	@within DeathReportServiceClient
	@param serviceBag ServiceBag
]=]
function DeathReportServiceClient.Init(self: DeathReportServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()

	-- Dependencies
	self._playerIdServiceClient = self._serviceBag:GetService(PlayerIdServiceClient)

	-- Internal client binder resolution
	self._serviceBag:GetService(DeathReportBindersClient)

	-- State
	self.NewDeathReport = self._maid:Add(Signal.new())
	self._reportProcessor = self._maid:Add(DeathReportProcessor.new())
	self._lastDeathReports = {}
end

--[=[
	Subscribes to ByteNet death report packets and resolves player IDs to adornes.

	@within DeathReportServiceClient
]=]
function DeathReportServiceClient.Start(self: DeathReportServiceClient): ()
	DeathReportNetwork.packets.deathReport.listen(function(data)
		local adornee: Instance? = data.adornee
		if not adornee and data.playerId then
			const player = PlayerIdServiceUtils.getPlayerFromId(data.playerId)
			if player then
				adornee = player.Character or player
			end
		end

		if not adornee then
			warn("[DeathReportServiceClient] - Failed to resolve adornee of deathReport. Probably not streamed in.")
			return
		end

		local killerAdornee: Instance? = data.killerAdornee
		if not killerAdornee and data.killerPlayerId then
			const killerPlayer = PlayerIdServiceUtils.getPlayerFromId(data.killerPlayerId)
			if killerPlayer then
				killerAdornee = killerPlayer.Character or killerPlayer
			end
		end

		const weaponData = DeathReportUtils.createWeaponData(data.weaponInstance)
		const deathReport = DeathReportUtils.create(adornee, killerAdornee, weaponData)
		self:_handleDeathReport(deathReport)
	end)
end

--[=[
	Observes killer reports for the given player.

	@within DeathReportServiceClient
	@param player Player
	@return Observable<DeathReport>
]=]
function DeathReportServiceClient.ObservePlayerKillerReports(
	self: DeathReportServiceClient,
	player: Player
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Player")(player), "Bad player")

	return self._reportProcessor:ObservePlayerKillerReports(player)
end

--[=[
	Observes death reports for the given player.

	@within DeathReportServiceClient
	@param player Player
	@return Observable<DeathReport>
]=]
function DeathReportServiceClient.ObservePlayerDeathReports(
	self: DeathReportServiceClient,
	player: Player
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Player")(player), "Bad player")

	return self._reportProcessor:ObservePlayerDeathReports(player)
end

--[=[
	Observes killer reports for the given humanoid.

	@within DeathReportServiceClient
	@param humanoid Humanoid
	@return Observable<DeathReport>
]=]
function DeathReportServiceClient.ObserveHumanoidKillerReports(
	self: DeathReportServiceClient,
	humanoid: Humanoid
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")

	return self._reportProcessor:ObserveHumanoidKillerReports(humanoid)
end

--[=[
	Observes death reports for the given humanoid.

	@within DeathReportServiceClient
	@param humanoid Humanoid
	@return Observable<DeathReport>
]=]
function DeathReportServiceClient.ObserveHumanoidDeathReports(
	self: DeathReportServiceClient,
	humanoid: Humanoid
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")

	return self._reportProcessor:ObserveHumanoidDeathReports(humanoid)
end

--[=[
	Observes killer reports for the given character model.

	@within DeathReportServiceClient
	@param character Model
	@return Observable<DeathReport>
]=]
function DeathReportServiceClient.ObserveCharacterKillerReports(
	self: DeathReportServiceClient,
	character: Model
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Model")(character), "Bad character")

	return self._reportProcessor:ObserveCharacterKillerReports(character)
end

--[=[
	Observes death reports for the given character model.

	@within DeathReportServiceClient
	@param character Model
	@return Observable<DeathReport>
]=]
function DeathReportServiceClient.ObserveCharacterDeathReports(
	self: DeathReportServiceClient,
	character: Model
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Model")(character), "Bad character")

	return self._reportProcessor:ObserveCharacterDeathReports(character)
end

--[=[
	Gets the recent list of recorded death reports (up to MAX_DEATH_REPORTS).

	@within DeathReportServiceClient
	@return { DeathReport }
]=]
function DeathReportServiceClient.GetLastDeathReports(self: DeathReportServiceClient): { DeathReportUtils.DeathReport }
	return self._lastDeathReports
end

function DeathReportServiceClient._handleDeathReport(
	self: DeathReportServiceClient,
	deathReport: DeathReportUtils.DeathReport
): ()
	assert(DeathReportUtils.isDeathReport(deathReport), "Bad deathReport")

	table.insert(self._lastDeathReports, deathReport)
	while #self._lastDeathReports > MAX_DEATH_REPORTS do
		table.remove(self._lastDeathReports, 1)
	end

	self.NewDeathReport:Fire(deathReport)
	self._reportProcessor:HandleDeathReport(deathReport)
end

--[=[
	Cleans up DeathReportServiceClient resources.

	@within DeathReportServiceClient
]=]
function DeathReportServiceClient.Destroy(self: DeathReportServiceClient): ()
	self._maid:DoCleaning()
end

return DeathReportServiceClient
