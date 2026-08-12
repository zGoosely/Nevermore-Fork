--!strict
--[=[
	Provides the server GameConfig and GameConfigAsset binders.

	@class GameConfigBindersServer
	@server
]=]

const require = require("../../Loader").load()

const Binder = require("Binder")
const BinderProvider = require("BinderProvider")
const ServiceBag = require("ServiceBag")

return BinderProvider.new("GameConfigBindersServer", function(self, serviceBag: ServiceBag.ServiceBag)
	self:Add(Binder.new("GameConfig", (require :: any)("GameConfig"), serviceBag))
	self:Add(Binder.new("GameConfigAsset", (require :: any)("GameConfigAsset"), serviceBag))
end)
