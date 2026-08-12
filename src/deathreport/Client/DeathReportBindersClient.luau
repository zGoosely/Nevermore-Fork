--!strict
--[=[
	Registers client-side death report binders with BinderProvider.

	@class DeathReportBindersClient
]=]

const require = require("../../Loader").load()

const Binder = require("Binder")
const BinderProvider = require("BinderProvider")
const PlayerDeathTrackerClient = require("PlayerDeathTrackerClient")
const PlayerKillTrackerClient = require("PlayerKillTrackerClient")
const ServiceBag = require("ServiceBag")
const TeamKillTrackerClient = require("TeamKillTrackerClient")

return BinderProvider.new("DeathReportBindersClient", function(self, serviceBag: ServiceBag.ServiceBag)
	-- Stats
	self:Add(Binder.new("TeamKillTracker", TeamKillTrackerClient :: any, serviceBag))
	self:Add(Binder.new("PlayerKillTracker", PlayerKillTrackerClient :: any, serviceBag))
	self:Add(Binder.new("PlayerDeathTracker", PlayerDeathTrackerClient :: any, serviceBag))
end)
