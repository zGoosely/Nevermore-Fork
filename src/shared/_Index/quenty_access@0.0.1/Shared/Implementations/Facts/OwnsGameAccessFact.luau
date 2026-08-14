--!strict
--[=[
	Whether the player has bought this game, from [GameProductDataService]. Pre-registered by
	[AccessDataService] as the fact behind [WellKnownAccessFeatureNames].OWNS_GAME.

	Registered at [AccessFactPriority].BUILT_IN, so a game that has its own idea of ownership layers over
	it rather than fighting it for the name.

	GOTCHA: ownership that cannot be resolved abstains rather than answering false. A marketplace hiccup
	must not read as "has not bought it" -- that is a paying player being turned away, which is the single
	worst outcome this package can produce.

	@class OwnsGameAccessFact
]=]
const AccessFact = require("../../AccessFact")
const AccessFactNames = require("../../AccessFactNames")
const AccessFactPriority = require("../../AccessFactPriority")
const GameProductDataService = require("@game/ReplicatedStorage/Packages/GameProductDataService")
const GameConfigAssetTypes = require("@game/ReplicatedStorage/Packages/GameConfigAssetTypes")
const Rx = require("@game/ReplicatedStorage/Packages/Rx")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local OwnsGameAccessFact = {}

local SOURCE = "purchase"
--[=[
	@param serviceBag ServiceBag
	@return AccessFact
]=]
function OwnsGameAccessFact.new(serviceBag: ServiceBag.ServiceBag): AccessFact.AccessFact
	assert(serviceBag, "No serviceBag")

	const gameProductDataService = serviceBag:GetService(GameProductDataService)

	return AccessFact.new(AccessFactNames.OWNS_GAME, {
		priority = AccessFactPriority.BUILT_IN,
		source = SOURCE,
		resolve = function(_serviceBag, player)
			return Rx.fromPromise(
				gameProductDataService:PromisePlayerOwnership(player, GameConfigAssetTypes.PASS, game.GameId)
			)
				:Pipe({
					Rx.catchError(function()
						return Rx.of(AccessFact.ABSTAIN :: any)
					end) :: any,
				})
		end,
	})
end

return OwnsGameAccessFact
