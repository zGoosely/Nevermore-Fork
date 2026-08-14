--!strict
--[=[
	Whether the player has admin permission, from the realm's permission service. Registered by the
	server and client access entry points so every game has it without additional setup.

	```lua
	AccessFeature.anyOf("chapters", { AccessFactNames.PLAYER_IS_ADMIN, "ownsGame" })
	```

	Registered at [AccessFactPriority].BUILT_IN -- the bottom -- so anything a game registers under the
	same name outranks it. A game with its own idea of who counts as staff layers over this rather than
	fighting it.

	The server and client entry points resolve their own permission service and pass it into this shared
	factory. Both realms therefore answer the same fact name without shared code importing a realm-only module.

	@class PlayerIsAdminAccessFact
]=]
const AccessFact = require("../../AccessFact")
const AccessFactNames = require("../../AccessFactNames")
const AccessFactPriority = require("../../AccessFactPriority")
const Rx = require("@game/ReplicatedStorage/Packages/Rx")
const RxAccessStateUtils = require("../../RxAccessStateUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

const PlayerIsAdminAccessFact = {}

local SOURCE = "permission"

--[=[
	Constructs the fact from the permission service resolved by the realm entry point.

	@param permissionService PermissionService or PermissionServiceClient
	@return AccessFact
]=]
function PlayerIsAdminAccessFact.new(permissionService: any): AccessFact.AccessFact
	assert(t.table(permissionService), "Bad permissionService")

	return AccessFact.new(AccessFactNames.PLAYER_IS_ADMIN, {
		priority = AccessFactPriority.BUILT_IN,
		source = SOURCE,
		resolve = function(_serviceBag, player)
			-- Abstains rather than answering when the permission system cannot speak for this player --
			-- an unconfigured provider, a web hiccup, or a mock in a test that a real provider rejects
			-- outright. Abstaining lets a game's own layer decide; answering "unresolved" would stop the
			-- fall-through, and answering false would silently lock staff out of their own game.
			--
			-- pcall as well as catchError: a provider that rejects a player does it by asserting during
			-- the call, which never becomes a stream failure for catchError to see.
			local ok, promise = pcall(function()
				return (permissionService :: any):PromiseIsAdmin(player)
			end)

			if not ok then
				return AccessFact.ABSTAIN
			end

			return Rx.fromPromise(promise):Pipe({
				Rx.catchError(function()
					return RxAccessStateUtils.ofStatic(AccessFact.ABSTAIN :: any)
				end) :: any,
			})
		end,
	})
end

return PlayerIsAdminAccessFact
