--!strict
--[=[
	Centralized death reporting service which can be used to track deaths on the server.

	@class DeathReportService
	@server
]=]

const require = require("../Loader").load()

const DeathReportBindersServer = require("DeathReportBindersServer")
const DeathReportNetwork = require("DeathReportNetwork")
const DeathReportProcessor = require("DeathReportProcessor")
const DeathReportUtils = require("DeathReportUtils")
const DeathTrackedHumanoid = require("DeathTrackedHumanoid")
const Maid = require("Maid")
const Observable = require("Observable")
const PlayerIdService = require("PlayerIdService")
const PlayerIdServiceUtils = require("PlayerIdServiceUtils")
const ServiceBag = require("ServiceBag")
const Signal = require("Signal")
const t = require("t")

const DeathReportService = {}
DeathReportService.ServiceName = "DeathReportService"
DeathReportService.ServerOnly = true

export type GetWeaponData = (humanoid: Humanoid) -> DeathReportUtils.WeaponData?

export type DeathReportService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		NewDeathReport: Signal.Signal<DeathReportUtils.DeathReport>,
		_playerIdService: PlayerIdService.PlayerIdService,
		_reportProcessor: DeathReportProcessor.DeathReportProcessor,
		_weaponDataRetrievers: { GetWeaponData },
	},
	{} :: typeof({ __index = DeathReportService })
))

--[=[
	Initializes the DeathReportService for the given service bag.

	@within DeathReportService
	@param serviceBag ServiceBag
]=]
function DeathReportService.Init(self: DeathReportService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()

	-- Dependencies
	self._playerIdService = self._serviceBag:GetService(PlayerIdService)

	-- Internal binder resolution
	self._serviceBag:GetService(DeathReportBindersServer)
	self._serviceBag:GetService(DeathTrackedHumanoid)

	-- Exported signals & state
	self.NewDeathReport = self._maid:Add(Signal.new())
	self._reportProcessor = self._maid:Add(DeathReportProcessor.new())
	self._weaponDataRetrievers = {}
end

--[=[
	Starts runtime connections for DeathReportService.

	@within DeathReportService
]=]
function DeathReportService.Start(_self: DeathReportService): () end

--[=[
	Adds a callback that returns custom weapon data for a dying humanoid.

	@within DeathReportService
	@param getWeaponData GetWeaponData
	@return () -> () -- Cleanup function to unregister retriever
]=]
function DeathReportService.AddWeaponDataRetriever(self: DeathReportService, getWeaponData: GetWeaponData): () -> ()
	assert(t.callback(getWeaponData), "Bad getWeaponData")

	table.insert(self._weaponDataRetrievers, getWeaponData)

	return function()
		const index = table.find(self._weaponDataRetrievers, getWeaponData)
		if index then
			table.remove(self._weaponDataRetrievers, index)
		end
	end
end

--[=[
	Searches registered weapon data retrievers for weapon information.

	@within DeathReportService
	@param humanoid Humanoid
	@return WeaponData?
]=]
function DeathReportService.FindWeaponData(self: DeathReportService, humanoid: Humanoid): DeathReportUtils.WeaponData?
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")

	for _, item in self._weaponDataRetrievers do
		const result = item(humanoid)
		if result then
			assert(DeathReportUtils.isWeaponData(result), "Failed to return valid weaponData")
			return result
		end
	end

	return nil
end

--[=[
	Observes killer reports for the given player.

	@within DeathReportService
	@param player Player
	@return Observable<DeathReport>
]=]
function DeathReportService.ObservePlayerKillerReports(
	self: DeathReportService,
	player: Player
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Player")(player), "Bad player")

	return self._reportProcessor:ObservePlayerKillerReports(player)
end

--[=[
	Observes death reports for the given player.

	@within DeathReportService
	@param player Player
	@return Observable<DeathReport>
]=]
function DeathReportService.ObservePlayerDeathReports(
	self: DeathReportService,
	player: Player
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Player")(player), "Bad player")

	return self._reportProcessor:ObservePlayerDeathReports(player)
end

--[=[
	Observes killer reports for the given humanoid.

	@within DeathReportService
	@param humanoid Humanoid
	@return Observable<DeathReport>
]=]
function DeathReportService.ObserveHumanoidKillerReports(
	self: DeathReportService,
	humanoid: Humanoid
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")

	return self._reportProcessor:ObserveHumanoidKillerReports(humanoid)
end

--[=[
	Observes death reports for the given humanoid.

	@within DeathReportService
	@param humanoid Humanoid
	@return Observable<DeathReport>
]=]
function DeathReportService.ObserveHumanoidDeathReports(
	self: DeathReportService,
	humanoid: Humanoid
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")

	return self._reportProcessor:ObserveHumanoidDeathReports(humanoid)
end

--[=[
	Observes killer reports for the given character model.

	@within DeathReportService
	@param character Model
	@return Observable<DeathReport>
]=]
function DeathReportService.ObserveCharacterKillerReports(
	self: DeathReportService,
	character: Model
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Model")(character), "Bad character")

	return self._reportProcessor:ObserveCharacterKillerReports(character)
end

--[=[
	Observes death reports for the given character model.

	@within DeathReportService
	@param character Model
	@return Observable<DeathReport>
]=]
function DeathReportService.ObserveCharacterDeathReports(
	self: DeathReportService,
	character: Model
): Observable.Observable<DeathReportUtils.DeathReport>
	assert(t.instanceIsA("Model")(character), "Bad character")

	return self._reportProcessor:ObserveCharacterDeathReports(character)
end

--[=[
	Reports the death of a humanoid.

	@within DeathReportService
	@param humanoid Humanoid
	@param weaponData WeaponData?
]=]
function DeathReportService.ReportHumanoidDeath(
	self: DeathReportService,
	humanoid: Humanoid,
	weaponData: DeathReportUtils.WeaponData?
): ()
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")

	const report = DeathReportUtils.fromDeceasedHumanoid(humanoid, weaponData or self:FindWeaponData(humanoid))
	self:ReportDeathReport(report)
end

--[=[
	Processes a death report and broadcasts it over ByteNet using compact Player IDs.

	@within DeathReportService
	@param deathReport DeathReport
]=]
function DeathReportService.ReportDeathReport(self: DeathReportService, deathReport: DeathReportUtils.DeathReport): ()
	assert(DeathReportUtils.isDeathReport(deathReport), "Bad deathReport")

	self.NewDeathReport:Fire(deathReport)
	self._reportProcessor:HandleDeathReport(deathReport)

	const playerId = if deathReport.player then PlayerIdServiceUtils.getId(deathReport.player) else nil
	const killerPlayerId = if deathReport.killerPlayer
		then PlayerIdServiceUtils.getId(deathReport.killerPlayer)
		else nil

	DeathReportNetwork.packets.deathReport.sendToAll({
		playerId = playerId,
		killerPlayerId = killerPlayerId,
		adornee = if playerId == nil then deathReport.adornee else nil,
		killerAdornee = if killerPlayerId == nil then deathReport.killerAdornee else nil,
		weaponInstance = if deathReport.weaponData then deathReport.weaponData.weaponInstance else nil,
	})
end

--[=[
	Cleans up DeathReportService resources.

	@within DeathReportService
]=]
function DeathReportService.Destroy(self: DeathReportService): ()
	self._maid:DoCleaning()
end

return DeathReportService
