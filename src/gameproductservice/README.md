# GameProductService

`GameProductDataService` is also available as a compatibility facade for packages that use the upstream
Nevermore purchase-data API. It delegates prompting, ownership, session purchase state, and purchase
observation to this fork's `GameProductService`/`GameProductServiceClient` implementations.

```luau
const GameProductDataService = require("GameProductDataService")

local dataService = serviceBag:GetService(GameProductDataService)
dataService:PromisePlayerOwnership(player, "pass", "x2Coins"):Then(function(owns)
	print("Owns pass:", owns)
end)
```

The compatibility layer supports the fork's `pass` and `product` asset types. Bundle, asset, membership,
and subscription trackers are not present in this repository.

`GameProductService` is the purchase boundary between `GameConfigService`, Roblox
`MarketplaceService`, and your game-specific fulfillment code. It resolves configured
asset keys, opens one purchase prompt per player, processes developer-product receipts,
caches pass ownership, and publishes server/client purchase signals.

The package intentionally supports game passes and developer products. Those two asset
types have different safety rules:

- A pass is a one-time Roblox-owned entitlement. `UserOwnsGamePassAsync` is the normal
  ownership source.
- A developer product can be purchased repeatedly and has no durable Roblox “owns”
  state. Fulfillment must happen from `MarketplaceService.ProcessReceipt`.
- `PromptProductPurchaseFinished(..., true)` is not proof of payment. The service only
  treats a product as purchased after a registered callback grants its receipt.
- An unhandled or failed product receipt returns `NotProcessedYet`, so Roblox can retry
  it instead of silently consuming a purchase.

## Setup

Load the realm-appropriate service through your `ServiceBag`:

```luau
-- Server
serviceBag:GetService(require("GameProductService"))

-- Client
serviceBag:GetService(require("GameProductServiceClient"))
```

The server service loads `GameConfigService`, `ReceiptProcessingService`, and Cmdr. The
client service loads `GameConfigServiceClient`.

Register assets with GameConfig before using their keys:

```luau
local GameConfigService = serviceBag:GetService(require("GameConfigService"))

GameConfigService:AddPass("x2Coins", 123456789)
GameConfigService:AddProduct("Coins100", 987654321)
```

## Developer-product fulfillment

Register one or more callbacks for a product. The first matching callback that grants or
retries claims the receipt.

```luau
local PlayerDataStoreService = serviceBag:GetService(require("PlayerDataStoreService"))
local GameProductService = serviceBag:GetService(require("GameProductService"))

self._maid:Add(GameProductService:RegisterProductCallback("Coins100", function(context)
	PlayerDataStoreService:SetValue(context.Player, "Coins", function(coins)
		return coins + 100
	end)

	-- A keyed callback that completes without returning is treated as granted.
end))
```

The callback receives:

```luau
{
	Player = player,
	AssetType = "product",
	AssetId = 987654321,
	AssetKey = "Coins100",
	PromptContext = {}, -- server-only context passed while prompting, if any
	ReceiptInfo = receiptInfo,
}
```

Callbacks can return:

- `GameProductHandlerResult.GRANT` or `true`: fulfillment is durably complete.
- `GameProductHandlerResult.RETRY` or `false`: stop processing and return
  `NotProcessedYet`.
- `GameProductHandlerResult.SKIP`: let the next callback inspect the purchase.
- A `Promise` resolving to one of those results.
- `nil`: grants for `RegisterProductCallback`/`RegisterPassCallback`, but skips for the
  generic `RegisterPurchaseProcessor` middleware API.

Receipt callbacks must be idempotent. Roblox can deliver the same receipt more than once
until your game returns `PurchaseGranted`. Use `context.ReceiptInfo.PurchaseId` as the
durable transaction key when a duplicate grant would matter.

## Generic purchase middleware

Middleware can claim purchases based on server-only prompt context. Gifting uses this to
route a product receipt to the selected recipient without also running the ordinary
buy-for-self callback.

```luau
local GameProductHandlerResult = require("GameProductHandlerResult")

self._maid:Add(GameProductService:RegisterPurchaseProcessor(function(context)
	local promptContext = context.PromptContext
	if type(promptContext) ~= "table" or promptContext.Kind ~= "SpecialOffer" then
		return GameProductHandlerResult.SKIP
	end

	return grantSpecialOffer(context.Player, promptContext):Then(function()
		return GameProductHandlerResult.GRANT
	end)
end, 100))
```

Higher priorities execute first. The registration function returns an idempotent cleanup
callback suitable for a `Maid`.

## Prompting

From the server:

```luau
GameProductService:PromptPurchaseAsync(player, "product", "Coins100", {
	Context = {
		Kind = "NormalShopPurchase",
		OfferId = "starter-pack",
	},
	Timeout = 300,
}):Then(function(purchased)
	print("Receipt granted:", purchased)
end):Catch(warn)
```

From the client:

```luau
local GameProductServiceClient = serviceBag:GetService(require("GameProductServiceClient"))

GameProductServiceClient:PromptPurchaseAsync("pass", "x2Coins")
	:Then(function(purchased)
		print("Pass purchase result:", purchased)
	end)
	:Catch(warn)
```

For products, the client promise stays pending after the prompt reports an attempted
purchase. It resolves true only when the server grants the receipt and sends the compact
ByteNet result.

Only one prompt is tracked per player. `IsPromptOpen(player)` on the server and
`IsPromptOpen()` on the client expose that state. Prompts default to a five-minute timeout
and accept a timeout from 1 to 900 seconds.

## Ownership

```luau
GameProductService:HasAssetAsync(player, "pass", "x2Coins")
	:Then(function(owns)
		print("Owns or has a custom entitlement:", owns)
	end)
```

Pass checks use a short negative cache and keep positive ownership cached for the session.
Call `InvalidateOwnership(player, passKey)` to force another Roblox query.

Products return true only when they were granted in the current session, unless an
ownership provider adds durable entitlement behavior. Gifting registers exactly such a
provider in both realms:

```luau
self._maid:Add(GameProductService:RegisterOwnershipProvider("pass", function(player, context)
	return MyEntitlementStore:HasAsync(player, context.AssetKey)
end, 100))
```

The client service exposes the same concept as
`RegisterOwnershipProvider(type, callback, priority?)`; its callback receives
`assetId, assetKey` for the local player.

Returning true owns the asset. False or nil falls through to the next provider and normal
Roblox ownership.

## Observation and signals

Server signals:

- `PurchaseGranted(player, assetType, assetId, context)`
- `GamePassPurchased(player, passId, context)`
- `ProductPurchased(player, productId, context)`

Client signals carry local-player data:

- `PurchaseGranted(assetType, assetId)`
- `GamePassPurchased(passId)`
- `ProductPurchased(productId)`

Targeted observation is also available:

```luau
self._maid:Add(GameProductService:ObservePlayerPurchase(player, "product", "Coins100")
	:Subscribe(function(context)
		print("Granted receipt", context.ReceiptInfo.PurchaseId)
	end))
```

`GetPurchaseCountThisSession` tracks repeat product grants. Pass counts remain one on the
client even though both the local prompt event and server confirmation can be observed.

## Cmdr

The server registers:

- `prompt-product players product`
- `prompt-pass players pass`

The `product` and `gamepass` Cmdr argument types fuzzy-search configured GameConfig
keys and parse the selected key into its underlying ID. Raw numeric IDs also work. Prompt
commands return per-player failures as their Cmdr response instead of raising an execution
error.

## API summary

### Server

| Method | Purpose |
| --- | --- |
| `RegisterPurchaseCallback(type, idOrKey, callback, priority?)` | Handles one pass or product. |
| `RegisterProductCallback(idOrKey, callback, priority?)` | Product convenience wrapper. |
| `RegisterPassCallback(idOrKey, callback, priority?)` | Pass convenience wrapper. |
| `RegisterPurchaseProcessor(callback, priority?)` | Adds context-aware middleware. |
| `RegisterOwnershipProvider(type, callback, priority?)` | Adds a custom entitlement source. |
| `PromptPurchaseAsync(player, type, idOrKey, options?)` | Opens and tracks a prompt. |
| `HasAssetAsync(player, type, idOrKey)` | Checks custom and normal ownership. |
| `GetPurchaseCountThisSession(...)` | Gets session grant count. |
| `ObservePlayerPurchase(...)` | Observes matching grants. |
| `IsPromptOpen(player)` | Checks prompt state. |
| `GetPendingPromptContext(player)` | Copies server-only pending context. |
| `InvalidateOwnership(player, pass)` | Clears a pass ownership cache entry. |

Compatibility aliases matching Nevermore naming are included:
`PromisePlayerPromptPurchase`, `PromisePlayerOwnership`, and
`HasPlayerPurchasedThisSession`.

### Client

| Method | Purpose |
| --- | --- |
| `PromptPurchaseAsync(type, idOrKey, timeout?)` | Prompts the local player. |
| `HasAssetAsync(type, idOrKey)` | Checks normal/session ownership. |
| `RegisterOwnershipProvider(type, callback, priority?)` | Adds a local entitlement source. |
| `GetPurchaseCountThisSession(type, idOrKey)` | Gets local observed count. |
| `ObservePurchase(type, idOrKey)` | Observes local grants. |
| `IsPromptOpen()` | Checks local prompt state. |
