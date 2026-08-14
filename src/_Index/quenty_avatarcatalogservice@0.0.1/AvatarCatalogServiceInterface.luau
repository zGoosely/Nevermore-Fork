--!strict
--[=[
	Defines the server contract used by avatar-catalog humanoid binders.

	@class AvatarCatalogServiceInterface
]=]

const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const TieDefinition = require("@game/ReplicatedStorage/Packages/TieDefinition")

export type AvatarCatalogServiceInterface = {
	EnforceAsync: (self: AvatarCatalogServiceInterface, humanoid: Humanoid) -> Promise.Promise<boolean>,
	ObserveUpdateRequested: (self: AvatarCatalogServiceInterface) -> Observable.Observable<number>,
}

return TieDefinition.new("AvatarCatalogService", {
	[TieDefinition.Realms.SERVER] = {
		EnforceAsync = TieDefinition.Types.METHOD,
		ObserveUpdateRequested = TieDefinition.Types.METHOD,
	},
}) :: TieDefinition.TieDefinition<AvatarCatalogServiceInterface>
