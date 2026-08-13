--!strict
--[=[
	Provides the server GameConfig and GameConfigAsset binders.

	@class GameConfigBindersServer
	@server
]=]
const Binder = require("@game/ReplicatedStorage/Packages/Binder")
const BinderProvider = require("@game/ReplicatedStorage/Packages/BinderProvider")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

return BinderProvider.new("GameConfigBindersServer", function(self, serviceBag: ServiceBag.ServiceBag)
	self:Add(Binder.new("GameConfig", (require :: any)("./Config/Config/GameConfig"), serviceBag))
	self:Add(Binder.new("GameConfigAsset", (require :: any)("./Config/Asset/GameConfigAsset"), serviceBag))
end)
