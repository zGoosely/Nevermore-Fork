# GiftingService

`GiftingService` stores virtual pass and developer-product entitlements under a player's
`Gifted` PlayerDataStoreService root. It uses GameConfig keys, enforces configurable social
restrictions, keeps server and client caches, serializes the client projection with
Squash, and can fulfill paid gifts through `GameProductService`.

Core metadata is stored with every gift:

```luau
Gifted = {
	Entitlements = {
		x2Coins = {
			AssetId = 123456789,
			AssetType = "pass",
			GiftedBy = 456789, -- user ID; 0 means a system grant
			GiftedAt = 1780000000,
			Quantity = 1,
			Metadata = {
				Source = "HolidayEvent",
			},
		},
	},
	PendingPurchases = {}, -- server-only, crash-aware paid gift intents
	ProcessedPurchases = {}, -- server-only receipt idempotency cache
}
```

The root is created automatically after PlayerDataStoreService loads a profile. It is hidden from
ordinary PlayerDataStoreService replication, so dynamic keys do not need to exist in `ProfileData.Schema`
and do not travel through ByteNet's generic `unknown` value. Only `Entitlements` reaches the
owning client through a compact package-specific buffer.

## Setup

Load the realm-appropriate service:

```luau
-- Server
local GiftingService = serviceBag:GetService(require("@game/ServerStorage/ServerPackages/GiftingService"))

-- Client
local GiftingServiceClient = serviceBag:GetService(require("@game/ReplicatedStorage/Packages/GiftingServiceClient"))
```

`GiftingService` loads `PlayerDataStoreService`, `GameConfigService`, and `GameProductService`.
`GiftingServiceClient` loads `GameProductServiceClient`.

Register the giftable assets in GameConfig:

```luau
local GameConfigService = serviceBag:GetService(require("@game/ServerStorage/ServerPackages/GameConfigService"))

GameConfigService:AddPass("x2Coins", 123456789)
GameConfigService:AddProduct("HealthPotion", 987654321)
```

Gift keys must be unambiguous. If a pass and product share the same key, pass
`AssetType = GiftingAssetTypes.GamePass` or `.Product` in the options table.

## Direct grants

The convenient form creates a system gift (`GiftedBy = 0`):

```luau
GiftingService:GiftAsync(player, "x2Coins")
	:Then(function(gift)
		print(gift.Quantity)
	end)
	:Catch(warn)
```

The options form is designed for gameplay, moderation, promotions, receipt processing,
and migrations:

```luau
local GiftingAssetTypes = require("@game/ReplicatedStorage/Packages/GiftingAssetTypes")
local GiftingDuplicateBehavior = require("@game/ReplicatedStorage/Packages/GiftingDuplicateBehavior")

GiftingService:GiftAsync(recipient, "HealthPotion", {
	AssetType = GiftingAssetTypes.Product,
	GiftedBy = gifter,
	Quantity = 3,
	DuplicateBehavior = GiftingDuplicateBehavior.Stack,
	Metadata = {
		Source = "Birthday",
		MessageId = "happy-birthday",
	},
}):Catch(warn)
```

Options:

| Field | Meaning |
| --- | --- |
| `AssetType` | Resolves an otherwise ambiguous key. |
| `GiftedBy` | `Player`, user ID, or nil for system. |
| `GiftedAt` | Override timestamp for trusted migrations. |
| `Quantity` | Positive integer, up to 1,000,000. |
| `Metadata` | JSON-safe custom table, up to 4096 encoded bytes. |
| `DuplicateBehavior` | `Keep`, `Replace`, or `Stack`. |
| `BypassRestriction` | Trusted server override for system/admin flows. |
| `AllowSelf` | Allows a supplied gifter to gift themselves. |
| `PurchaseId` | Makes receipt fulfillment idempotent. |

The default duplicate policy is `Keep` for passes and `Stack` for products. This keeps a
pass as a single entitlement while allowing repeatable product gifts to carry quantity.

## Restrictions

The default is unrestricted gifting:

```luau
local GiftingRestrictions = require("@game/ReplicatedStorage/Packages/GiftingRestrictions")

GiftingService:SetPlayerGiftRestriction(GiftingRestrictions.All)
```

Require friendship globally:

```luau
GiftingService:SetPlayerGiftRestriction(GiftingRestrictions.Friends)
```

Set one online player's override:

```luau
GiftingService:SetPlayerGiftRestriction(player, GiftingRestrictions.Friends)
```

Friend restrictions are verified on the server with `FriendUtils` immediately before a
grant. The restriction belongs to the gifter. System grants with no `GiftedBy` player are
allowed; trusted admin flows can use `BypassRestriction = true`.

Preflight a UI flow without changing data:

```luau
GiftingService:CanGiftAsync(gifter, recipient, "x2Coins")
	:Then(function(allowed, reason)
		if not allowed then
			warn(reason)
		end
	end)
```

## Paid gifts

Roblox cannot sell a game pass to a different recipient. To gift a pass for Robux, create
a developer product at the desired price and map it to the pass entitlement:

```luau
GameConfigService:AddPass("x2Coins", 123456789)
GameConfigService:AddProduct("GiftX2Coins", 222333444)

GiftingService:RegisterGiftProduct("x2Coins", "GiftX2Coins")
```

Then prompt the gifter from trusted server code:

```luau
GiftingService:PromptGiftAsync(gifter, recipient, "x2Coins", {
	Metadata = {
		Shop = "MainMenu",
	},
}):Then(function(purchased)
	print("Paid gift granted:", purchased)
end):Catch(warn)
```

Product gifts use their own product key by default, or can specify another charging
product:

```luau
GiftingService:PromptGiftAsync(gifter, recipient, "HealthPotion", {
	PurchaseProduct = "GiftPotionPack",
	Quantity = 5,
})
```

The paid flow:

1. Verifies configuration, self-gifting, and friendship restrictions.
2. Persists a pending gift intent on the gifter before opening the prompt.
3. Passes only an opaque context ID into `GameProductService`.
4. Waits for `ProcessReceipt`; prompt-finished is never treated as payment proof.
5. Grants the recipient through ordinary `GiftAsync`.
6. Records `PurchaseId` before acknowledging the receipt, preventing duplicate quantity.
7. Removes the pending intent and returns `PurchaseGranted`.

The recipient must currently be online because this PlayerDataStoreService only owns loaded player
profiles. If the recipient leaves during checkout, the receipt returns `NotProcessedYet`
instead of losing the purchase. A receipt being retried is not rejected merely because
the intent is old. Abandoned intents older than 15 minutes are pruned when another paid
gift begins, and only one unresolved intent may use a given charging product at a time so
restart recovery stays deterministic. Supporting offline recipients would require an
offline profile-update boundary or a durable delivery queue; it should not be simulated
by granting from the prompt event.

## Checking entitlements

Use `HasGiftAsync` when you specifically care about the virtual gift:

```luau
GiftingService:HasGiftAsync(player, "x2Coins"):Then(print)
```

Use `HasEntitlementAsync` for normal gameplay permission checks. It returns true when the
player has either the persisted gift or normal ownership from GameProductService:

```luau
GiftingService:HasEntitlementAsync(player, "x2Coins"):Then(function(hasX2)
	if hasX2 then
		enableDoubleCoins(player)
	end
end)
```

Gifting also registers itself as a GameProductService ownership provider in both realms,
so this works:

```luau
GameProductService:HasAssetAsync(player, "pass", "x2Coins")
```

Developer products do not have normal durable Roblox ownership. A gifted product behaves
as a quantity-backed virtual entitlement.

## Removing and consuming gifts

Remove the entire record:

```luau
GiftingService:RemoveGiftAsync(player, "x2Coins")
```

Decrement a quantity, deleting the record when it reaches zero:

```luau
GiftingService:RemoveGiftAsync(player, "HealthPotion", 2)
GiftingService:ConsumeGiftAsync(player, "HealthPotion") -- consumes one
```

Both resolve with whether a record existed.

## Server observation

Observe a copied map:

```luau
self._maid:Add(GiftingService:ObserveGifts(player):Subscribe(function(gifts)
	print(gifts.x2Coins)
end))
```

Observe stable individual lifetimes:

```luau
self._maid:Add(GiftingService:ObserveGiftsBrio(player):Subscribe(function(brio)
	local maid, assetKey, gift = brio:ToMaidAndValue()
	print("Gift added or changed", assetKey, gift.Quantity)

	maid:Add(function()
		print("Gift removed or replaced", assetKey)
	end)
end))
```

Changing one gift only replaces that gift's Brio; unrelated gifts retain their lifetimes.

## Client cache and observers

Wait for the initial snapshot when making a synchronous read during startup:

```luau
GiftingServiceClient:ReadyAsync():Then(function()
	print(GiftingServiceClient:HasGift("x2Coins"))
	print(GiftingServiceClient:GetGift("x2Coins"))
	print(GiftingServiceClient:GetGifts())
end)
```

Observe the complete map:

```luau
self._maid:Add(GiftingServiceClient:ObserveGifts():Subscribe(function(gifts)
	print("Gift count changed", gifts)
end))
```

Observe individual gifts:

```luau
self._maid:Add(GiftingServiceClient:ObserveGiftsBrio():Subscribe(function(brio)
	local maid, assetKey, gift = brio:ToMaidAndValue()
	print(assetKey, gift.GiftedBy, gift.GiftedAt, gift.Quantity)
end))
```

Observe a single key or boolean:

```luau
self._maid:Add(GiftingServiceClient:ObserveGift("x2Coins"):Subscribe(function(gift)
	print("Gift record", gift)
end))

self._maid:Add(GiftingServiceClient:ObserveHasGift("x2Coins"):Subscribe(function(hasGift)
	setDoubleCoinsBadgeVisible(hasGift)
end))
```

Filter by pass or product:

```luau
local GiftingAssetTypes = require("@game/ReplicatedStorage/Packages/GiftingAssetTypes")

self._maid:Add(GiftingServiceClient:ObserveGiftsType(GiftingAssetTypes.GamePass)
	:Subscribe(function(passGifts)
		print(passGifts)
	end))

self._maid:Add(GiftingServiceClient:ObserveGiftsTypeBrio(GiftingAssetTypes.Product)
	:Subscribe(function(brio)
		local maid, assetKey, gift = brio:ToMaidAndValue()
		showConsumableGift(assetKey, gift.Quantity)
	end))
```

Client entitlement checks combine the gift cache with normal product-service ownership:

```luau
GiftingServiceClient:HasEntitlementAsync("x2Coins", GiftingAssetTypes.GamePass)
	:Then(print)
```

## Caching and replication

- PlayerDataStoreService remains the server-authoritative persistence cache.
- The server keeps one normalized root and one `ObservableMap` per loaded player.
- The client keeps one read-only `ObservableMap` for its own gifts.
- Static record field names are encoded by Squash schemas and cost no string bytes.
- The root's pending intents and processed receipt IDs never replicate.
- Sequence numbers prevent an older query response from overwriting a newer push packet.
- Public reads and observer emissions deep-copy records so consumers cannot mutate caches.

## Cmdr

The server registers:

- `gift players assetKey [quantity]`
- `remove-gift players assetKey [quantity]`
- `has-gift player assetKey`
- `list-gifts player`

Cmdr grants record the executor as `GiftedBy`, add `Metadata.Source = "Cmdr"`, and bypass
friend restrictions because Cmdr is already protected by the admin permission hook. Every
command returns a readable success, partial-success, or failure response instead of raising
an execution error for an expected service failure.

## API summary

### Server

| Method | Purpose |
| --- | --- |
| `GiftAsync(player, key, options?)` | Grants or updates a gift. |
| `PromptGiftAsync(gifter, recipient, key, options?)` | Runs a receipt-safe paid gift. |
| `CanGiftAsync(gifter, recipient, key, options?)` | Preflights restrictions. |
| `HasGiftAsync(player, key)` | Checks only persisted gifted state. |
| `HasEntitlementAsync(player, key, type?)` | Checks gifted or normal ownership. |
| `GetGiftAsync(player, key)` | Gets one copied record. |
| `GetGiftsAsync(player)` | Gets every copied record. |
| `RemoveGiftAsync(player, key, quantity?)` | Removes or decrements. |
| `ConsumeGiftAsync(player, key, quantity?)` | Consumes quantity, default one. |
| `ObserveGifts(player)` | Observes a copied map. |
| `ObserveGiftsBrio(player)` | Observes individual lifetimes. |
| `SetPlayerGiftRestriction(...)` | Sets global or per-player policy. |
| `GetPlayerGiftRestriction(player?)` | Gets effective policy. |
| `RegisterGiftProduct(key, product, type?)` | Maps charging product to entitlement. |

### Client

| Method | Purpose |
| --- | --- |
| `ReadyAsync()` | Waits for initial cache. |
| `GetGifts()` / `GetGift(key)` / `HasGift(key)` | Synchronous cached reads. |
| `HasEntitlementAsync(key, type)` | Checks gifted or normal ownership. |
| `ObserveGifts()` | Observes complete maps. |
| `ObserveGiftsBrio()` | Observes individual gifts. |
| `ObserveGift(key)` / `ObserveHasGift(key)` | Observes one entitlement. |
| `ObserveGiftsType(type)` | Observes a filtered map. |
| `ObserveGiftsTypeBrio(type)` | Observes filtered individual lifetimes. |
