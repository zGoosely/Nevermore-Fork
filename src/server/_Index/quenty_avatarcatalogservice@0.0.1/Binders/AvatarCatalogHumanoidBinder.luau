--!strict
--[=[
	Binds avatar-catalog enforcement to every player humanoid.

	@class AvatarCatalogHumanoidBinder
	@server
]=]

const PlayerHumanoidBinder = require("@game/ReplicatedStorage/Packages/PlayerHumanoidBinder")

const AvatarCatalogHumanoid = require("./AvatarCatalogHumanoid")

return PlayerHumanoidBinder.new("AvatarCatalogHumanoid", AvatarCatalogHumanoid)
