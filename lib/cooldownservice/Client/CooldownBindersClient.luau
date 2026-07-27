--!strict
--[=[
	Provides the replicated and predicted client Cooldown binder.

	@class CooldownBindersClient
	@client
]=]

const require = require("../../Loader").load()

const Binder = require("Binder")
const BinderProvider = require("BinderProvider")
const CooldownClient = require("CooldownClient")
const CooldownClockService = require("CooldownClockService")
const CooldownServiceConstants = require("CooldownServiceConstants")
const ServiceBag = require("ServiceBag")

export type CooldownBindersClient = {
	_cooldownClockService: CooldownClockService.CooldownClockService,
	Cooldown: Binder.Binder<CooldownClient.CooldownClient>,
}

return BinderProvider.new("CooldownBindersClient", function(self, serviceBag: ServiceBag.ServiceBag)
	const cooldownClockService = serviceBag:GetService(CooldownClockService)
	const typedSelf = self :: any
	typedSelf._cooldownClockService = cooldownClockService
	const clock = function()
		return cooldownClockService:GetTime()
	end

	self:Add(Binder.new(CooldownServiceConstants.TAG_NAME, function(instance)
		return CooldownClient.new(instance :: Folder, clock)
	end))
end)
