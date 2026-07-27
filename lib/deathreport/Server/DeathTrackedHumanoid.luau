--!strict
--[=[
	Tracks deaths on humanoids and reports them to DeathReportService.

	@class DeathTrackedHumanoid
]=]

const require = require("../../Loader").load()

const BaseObject = require("BaseObject")
const DeathReportService = require("DeathReportService")
const PlayerHumanoidBinder = require("PlayerHumanoidBinder")
const ServiceBag = require("ServiceBag")
const t = require("t")

const DeathTrackedHumanoid = setmetatable({}, BaseObject)
DeathTrackedHumanoid.ClassName = "DeathTrackedHumanoid"
DeathTrackedHumanoid.__index = DeathTrackedHumanoid

export type DeathTrackedHumanoid =
	typeof(setmetatable(
		{} :: {
			_obj: Humanoid,
			_serviceBag: ServiceBag.ServiceBag,
			_deathReportService: DeathReportService.DeathReportService,
			_diedEvent: RBXScriptConnection?,
		},
		{} :: typeof({ __index = DeathTrackedHumanoid })
	))
	& BaseObject.BaseObject

function DeathTrackedHumanoid.new(humanoid: Humanoid, serviceBag: ServiceBag.ServiceBag): DeathTrackedHumanoid
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")
	assert(t.table(serviceBag), "Bad serviceBag")

	const self: DeathTrackedHumanoid = setmetatable(BaseObject.new(humanoid) :: any, DeathTrackedHumanoid)

	self._serviceBag = serviceBag
	self._deathReportService = self._serviceBag:GetService(DeathReportService)

	self._diedEvent = self._maid:Add(self._obj:GetPropertyChangedSignal("Health"):Connect(function()
		self:_handleDeath()
	end))

	return self
end

function DeathTrackedHumanoid._handleDeath(self: DeathTrackedHumanoid): ()
	if not self._diedEvent then
		return
	end

	if self._obj.Health <= 0 then
		if self._diedEvent then
			self._maid[self._diedEvent] = nil
			self._diedEvent = nil
		end
		self._deathReportService:ReportHumanoidDeath(self._obj)
	end
end

function DeathTrackedHumanoid.Destroy(self: DeathTrackedHumanoid): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return PlayerHumanoidBinder.new("DeathTrackedHumanoid", DeathTrackedHumanoid :: any)
