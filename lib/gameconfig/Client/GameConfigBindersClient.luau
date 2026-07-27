--!strict
--[=[
	Provides the client GameConfig and GameConfigAsset binders.

	@class GameConfigBindersClient
	@client
]=]

const require = require("../../Loader").load()

const Binder = require("Binder")
const BinderProvider = require("BinderProvider")
const ServiceBag = require("ServiceBag")

return BinderProvider.new("GameConfigBindersClient", function(self, serviceBag: ServiceBag.ServiceBag)
	self:Add(Binder.new("GameConfig", (require :: any)("GameConfigClient"), serviceBag))
	self:Add(Binder.new("GameConfigAsset", (require :: any)("GameConfigAssetClient"), serviceBag))
end)
