--!strict
--[=[
	Provides the client GameConfig and GameConfigAsset binders.

	@class GameConfigBindersClient
	@client
]=]
const Binder = require("@game/ReplicatedStorage/Packages/Binder")
const BinderProvider = require("@game/ReplicatedStorage/Packages/BinderProvider")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

return BinderProvider.new("GameConfigBindersClient", function(self, serviceBag: ServiceBag.ServiceBag)
	self:Add(Binder.new("GameConfig", (require :: any)("./Config/Config/GameConfigClient"), serviceBag))
	self:Add(Binder.new("GameConfigAsset", (require :: any)("./Config/Asset/GameConfigAssetClient"), serviceBag))
end)
