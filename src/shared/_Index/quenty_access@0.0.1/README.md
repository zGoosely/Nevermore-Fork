# Access

Access provides named, inspectable feature gates. A fact answers what is true about a player; a feature
combines facts and decides whether a capability is allowed; a policy performs a side effect such as
kicking a player.

This package is adapted from [NevermoreEngine's access package](https://github.com/Quenty/NevermoreEngine/tree/main/src/access)
for this fork's loader, package layout, and available services.

This fork uses the repository loader and the existing `Tie` package. Replication is carried by JSON
attributes on `Player` and `ReplicatedStorage`; the package does not add a ByteNet or Remoting schema.

## Installation

Include `lib/access` in your Rojo project and initialize the realm entry point with `ServiceBag`:

```luau
-- Server
const AccessService = require("@game/ReplicatedStorage/Packages/AccessService")

serviceBag:GetService(AccessService)

-- Client
const AccessServiceClient = require("@game/ReplicatedStorage/Packages/AccessServiceClient")

serviceBag:GetService(AccessServiceClient)
```

Register facts and features from a shared service during `Init`, after resolving `AccessDataService`:

```luau
const AccessDataService = require("@game/ReplicatedStorage/Packages/AccessDataService")
const AccessFact = require("@game/ReplicatedStorage/Packages/AccessFact")
const AccessFeature = require("@game/ReplicatedStorage/Packages/AccessFeature")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local ShopAccessService = {}
ShopAccessService.ServiceName = "ShopAccessService"

function ShopAccessService.Init(self, serviceBag: ServiceBag.ServiceBag)
	self._maid = Maid.new()
	self._accessDataService = serviceBag:GetService(AccessDataService)

	local testerFact = self._maid:Add(AccessFact.new("isTester", {
		priority = 100,
		source = "testers",
		resolve = function(_serviceBag, player)
			return player:GetAttribute("IsTester") == true
		end,
	}))

	local shopFeature = self._maid:Add(AccessFeature.anyOf("shop", { "isTester" }))
	self._maid:GiveTask(self._accessDataService:RegisterFact(testerFact))
	self._maid:GiveTask(self._accessDataService:RegisterFeature(shopFeature))
end

return ShopAccessService
```

## Checking access

Use `AccessPlayerInterface` when you already have a player, or observe the feature directly through
`AccessDataService` when you are building a service-level workflow:

```luau
const AccessPlayerInterface = require("@game/ReplicatedStorage/Packages/AccessPlayerInterface")

local accessPlayer = AccessPlayerInterface:Find(player)
if accessPlayer and accessPlayer:IsFeatureAllowedByName("shop") then
	-- Show or open the shop.
end
```

For UI and purchase flows, prefer the full tri-state result so unresolved is not mistaken for denial:

```luau
const AccessDataService = require("@game/ReplicatedStorage/Packages/AccessDataService")
const AccessStateUtils = require("@game/ReplicatedStorage/Packages/AccessStateUtils")

local accessDataService = serviceBag:GetService(AccessDataService)
accessDataService:ObserveFeature(player, shopFeature):Subscribe(function(state)
	if AccessStateUtils.isAllowed(state) then
		print("Shop available")
	elseif AccessStateUtils.isUnresolved(state) then
		print("Still checking access")
	else
		print("Shop unavailable")
	end
end)
```

## Adding another way in

Features can be widened without editing their original definition:

```luau
const FeatureAccessFact = require("@game/ReplicatedStorage/Packages/FeatureAccessFact")

local earlyAccessFact = self._maid:Add(AccessFact.new("earlyAccess", {
	priority = 100,
	source = "event",
	resolve = function(_serviceBag, player)
		return player:GetAttribute("EarlyAccess") == true
	end,
}))

self._maid:GiveTask(self._accessDataService:RegisterFact(earlyAccessFact))
self._maid:GiveTask(shopFeature:PushFactAllowsFeature(earlyAccessFact))
```

`PushFactAllowsFeature` only widens a feature. It can grant access but never turn an existing grant into a
denial.

## Policies

Policies are the side-effect layer. Register one when enforcement is desired, and leave it disabled when
the feature is only being used for presentation:

```luau
const AccessFactNames = require("@game/ReplicatedStorage/Packages/AccessFactNames")
const AccessKickPolicy = require("@game/ReplicatedStorage/Packages/AccessKickPolicy")
const AccessPolicyService = require("@game/ReplicatedStorage/Packages/AccessPolicyService")

const policyService = serviceBag:GetService(AccessPolicyService)
const policy = self._maid:Add(AccessKickPolicy.whenFactIs(
	serviceBag,
	"kick-on-non-admin",
	AccessFactNames.PLAYER_IS_ADMIN,
	false,
	{ message = "This place is limited to the development team." }
))

self._maid:GiveTask(policyService:RegisterPolicy(policy))
```

Policies never act on unresolved facts. This prevents a temporary permission or marketplace failure from
being treated as a definite denial.

## Replication and networking

The server writes resolved facts, overrides, and feature metadata to JSON attributes. Clients consume those
attributes through the player binders and the shared `AccessDataService`. Tie interfaces expose the public
query API. No ByteNet packet or separate Remoting object is required by this package.

The built-in `ownsGame` fact intentionally abstains because this fork does not include
`GameProductDataService`. Register a purchase resolver at a higher priority when your game has one.
