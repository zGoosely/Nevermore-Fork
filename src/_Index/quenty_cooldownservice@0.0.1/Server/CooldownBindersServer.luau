--!strict
--[=[
	Provides the authoritative server Cooldown binder.

	@class CooldownBindersServer
	@server
]=]
const Binder = require("@game/ReplicatedStorage/Packages/Binder")
const BinderProvider = require("@game/ReplicatedStorage/Packages/BinderProvider")
const Cooldown = require("./Cooldown")
const CooldownClockService = require("../Shared/CooldownClockService")
const CooldownServiceConstants = require("../Shared/CooldownServiceConstants")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

export type CooldownBindersServer = {
	_cooldownClockService: CooldownClockService.CooldownClockService,
	Cooldown: Binder.Binder<Cooldown.Cooldown>,
}

return BinderProvider.new("CooldownBindersServer", function(self, serviceBag: ServiceBag.ServiceBag)
	const cooldownClockService = serviceBag:GetService(CooldownClockService)
	const typedSelf = self :: any
	typedSelf._cooldownClockService = cooldownClockService
	const clock = function()
		return cooldownClockService:GetTime()
	end

	self:Add(Binder.new(CooldownServiceConstants.TAG_NAME, function(instance)
		return Cooldown.new(instance :: Folder, clock)
	end))
end)
