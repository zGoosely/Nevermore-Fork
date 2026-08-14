--!strict
--[=[
	Registers server-side death report binders with BinderProvider.

	@class DeathReportBindersServer
]=]
const Binder = require("@game/ReplicatedStorage/Packages/Binder")
const BinderProvider = require("@game/ReplicatedStorage/Packages/BinderProvider")
const PlayerDeathTracker = require("./Stats/PlayerDeathTracker")
const PlayerKillTracker = require("./Stats/PlayerKillTracker")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const TeamKillTracker = require("./Stats/TeamKillTracker")

return BinderProvider.new("DeathReportBindersServer", function(self, serviceBag: ServiceBag.ServiceBag)
	-- Stats
	self:Add(Binder.new("TeamKillTracker", TeamKillTracker :: any, serviceBag))
	self:Add(Binder.new("PlayerKillTracker", PlayerKillTracker :: any, serviceBag))
	self:Add(Binder.new("PlayerDeathTracker", PlayerDeathTracker :: any, serviceBag))
end)
