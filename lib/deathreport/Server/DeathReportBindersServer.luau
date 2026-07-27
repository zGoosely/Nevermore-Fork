--!strict
--[=[
	Registers server-side death report binders with BinderProvider.

	@class DeathReportBindersServer
]=]

const require = require("../../Loader").load()

const Binder = require("Binder")
const BinderProvider = require("BinderProvider")
const PlayerDeathTracker = require("PlayerDeathTracker")
const PlayerKillTracker = require("PlayerKillTracker")
const ServiceBag = require("ServiceBag")
const TeamKillTracker = require("TeamKillTracker")

return BinderProvider.new("DeathReportBindersServer", function(self, serviceBag: ServiceBag.ServiceBag)
	-- Stats
	self:Add(Binder.new("TeamKillTracker", TeamKillTracker :: any, serviceBag))
	self:Add(Binder.new("PlayerKillTracker", PlayerKillTracker :: any, serviceBag))
	self:Add(Binder.new("PlayerDeathTracker", PlayerDeathTracker :: any, serviceBag))
end)
