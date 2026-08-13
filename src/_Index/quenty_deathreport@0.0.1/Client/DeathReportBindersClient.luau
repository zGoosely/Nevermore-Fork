--!strict
--[=[
	Registers client-side death report binders with BinderProvider.

	@class DeathReportBindersClient
]=]
const Binder = require("@game/ReplicatedStorage/Packages/Binder")
const BinderProvider = require("@game/ReplicatedStorage/Packages/BinderProvider")
const PlayerDeathTrackerClient = require("./Stats/PlayerDeathTrackerClient")
const PlayerKillTrackerClient = require("./Stats/PlayerKillTrackerClient")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const TeamKillTrackerClient = require("./Stats/TeamKillTrackerClient")

return BinderProvider.new("DeathReportBindersClient", function(self, serviceBag: ServiceBag.ServiceBag)
	-- Stats
	self:Add(Binder.new("TeamKillTracker", TeamKillTrackerClient :: any, serviceBag))
	self:Add(Binder.new("PlayerKillTracker", PlayerKillTrackerClient :: any, serviceBag))
	self:Add(Binder.new("PlayerDeathTracker", PlayerDeathTrackerClient :: any, serviceBag))
end)
