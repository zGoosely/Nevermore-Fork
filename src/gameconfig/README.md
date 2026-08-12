# GameConfigService

`GameConfigService` gives the rest of the game stable names for Roblox-owned
IDs. Code can ask for `"DoubleCoins"` instead of carrying a game-pass ID through
every system. The same configuration is available on the server and client and
can change while the server is running.

The service supports badges, developer products, passes, catalog assets,
bundles, places, subscriptions, and membership entries.

## How replication works

The server stores configuration in `ReplicatedStorage.GameConfigs` using tagged
Folders and attributes. Roblox replicates those instances naturally. The client
binders turn the replicated Folders into the same queryable model API.

There is no ByteNet packet containing the entire configuration. Adding,
changing, reparenting, renaming, or destroying an asset produces only the normal
Roblox instance/attribute replication for that change.

## Registering assets on the server

Retrieve `GameConfigService` during another service's `Init` method and register
the IDs used by the current experience:

```luau
const GameConfigService = require("GameConfigService")

function ShopService.Init(self: ShopService, serviceBag: ServiceBag.ServiceBag)
	self._gameConfigService = serviceBag:GetService(GameConfigService)

	self._gameConfigService:AddBadge("FirstWin", 123456789)
	self._gameConfigService:AddProduct("CoinPackSmall", 234567890)
	self._gameConfigService:AddPass("DoubleCoins", 345678901)
	self._gameConfigService:AddPlace("Dungeon", 456789012)
	self._gameConfigService:AddAsset("ShopIcon", 567890123)
	self._gameConfigService:AddBundle("StarterAvatar", 678901234)
	self._gameConfigService:AddSubscription("VIP", "EXP-00000000")
end
```

Registration is idempotent inside the default configuration. Registering
`"DoubleCoins"` again updates its ID instead of creating another Folder with the
same name.

Use `AddTypedAsset` when the asset type is selected dynamically:

```luau
const GameConfigAssetTypes = require("GameConfigAssetTypes")

gameConfigService:AddTypedAsset(
	GameConfigAssetTypes.PRODUCT,
	"CoinPackLarge",
	789012345
)
```

`RemoveTypedAsset(assetType, assetKey)` removes a registration from the default
configuration.

## Looking up assets

Both realm services expose a `GameConfigPicker`:

```luau
-- Server
const picker = gameConfigService:GetConfigPicker()

-- Client
const GameConfigServiceClient = require("GameConfigServiceClient")
const service = serviceBag:GetService(GameConfigServiceClient)
const picker = service:GetConfigPicker()
```

Synchronous lookup is appropriate when registration is known to be complete:

```luau
const GameConfigAssetTypes = require("GameConfigAssetTypes")

const pass = picker:FindFirstActiveAssetOfKey(
	GameConfigAssetTypes.PASS,
	"DoubleCoins"
)

if pass then
	print(pass:GetAssetId())
	print(pass:GetAssetKey())
	print(pass:GetAssetType())
end

const passId = picker:ToAssetId(GameConfigAssetTypes.PASS, "DoubleCoins")
```

Numeric identifiers passed to `ToAssetId` are returned directly. String values
normally mean an asset key. Subscription and membership identifiers are also
strings, so an unmatched key is treated as a direct identifier for those two
types.

## Observing dynamic configuration

Reactive methods emit Brios so removal and replacement have an explicit
lifetime:

```luau
const Maid = require("Maid")
const RxBrioUtils = require("RxBrioUtils")
const RxStateStackUtils = require("RxStateStackUtils")

const maid = Maid.new()

const activePass = maid:Add(RxStateStackUtils.createStateStack(
	picker:ObserveActiveAssetOfAssetTypeAndKeyBrio(
		GameConfigAssetTypes.PASS,
		"DoubleCoins"
	)
))

maid:GiveTask(activePass:Observe():Subscribe(function(pass)
	print("Current pass:", pass and pass:GetAssetId())
end))
```

Other picker observations include:

- `ObserveActiveConfigsBrio()`
- `ObserveConfigsForGameIdBrio(gameId)`
- `ObserveActiveAssetOfTypeBrio(assetType)`
- `ObserveActiveAssetOfAssetTypeAndIdBrio(assetType, assetId)`
- `ObserveActiveAssetOfAssetIdBrio(assetId)`
- `ObserveActiveAssetOfKeyBrio(assetKey)`
- `ObserveToAssetIdBrio(assetType, assetIdOrKey)`

## Cloud metadata

An asset model can observe or promise metadata retrieved from Roblox:

```luau
maid:GiveTask(pass:ObserveCloudName():Subscribe(print))
maid:GiveTask(pass:ObserveCloudPriceInRobux():Subscribe(print))
maid:GiveTask(pass:ObserveCloudIconImageAssetId():Subscribe(print))

pass:PromiseCloudPriceInRobux()
	:Then(function(price)
		print("Price:", price)
	end)
	:Catch(warn)
```

Marketplace requests share `MarketplaceServiceCache`, including concurrent
requests for the same ID and info type. Failed requests are removed from the
cache so a future lookup can retry. Badge metadata uses `BadgeService`.
Subscription metadata uses
`MarketplaceService:GetSubscriptionProductInfoAsync`. Membership entries resolve
cloud metadata to `nil` because they represent a membership state rather than a
marketplace product.

The server derives name and description localization keys from cloud metadata.
These can be observed with `ObserveTranslatedName()` and
`ObserveTranslatedDescription()`.

## Multiple configurations

`CreateConfig(gameId, configName)` creates another configuration. A picker only
treats configurations whose `GameId` matches `game.GameId` as active, while
`GetConfigsForGameId` and `ObserveConfigsForGameIdBrio` can inspect another game
ID explicitly.

```luau
const staging = gameConfigService:CreateConfig(game.GameId, "Staging")
```

To populate a non-default config directly, use `GameConfigAssetUtils.create`
with `GameConfigBindersServer.GameConfigAsset`, then parent the result beneath
the appropriate plural asset folder returned by
`GameConfigUtils.getOrCreateAssetFolder`.

## Studio-authored Folder configuration

The service can bind a manually-authored Folder with
`RegisterConfigFolder(configFolder)`. When the service starts, it also scans
direct child Folders under `ReplicatedStorage.GameConfigs`.

The expected structure is:

```text
GameConfigs
└── MyConfig                         GameId = 123
    ├── badges
    │   └── FirstWin                AssetId = 123456789
    ├── products
    ├── passes
    │   └── DoubleCoins             AssetId = 345678901
    ├── assets
    ├── bundles
    ├── places
    ├── subscriptions
    └── memberships
```

`RegisterConfigFolder` applies the `GameConfig` and `GameConfigAsset` tags and
fills each asset's `AssetType` attribute from its parent folder. Build the Folder
completely before parenting it, or call `RegisterConfigFolder` explicitly after
setting its attributes.

## Mantle

`MantleConfigProvider.new(container)` is a ServiceBag component. Every direct
child ModuleScript in the container must return Mantle output data. The provider
creates one replicated configuration per module.

```luau
const MantleConfigProvider = require("MantleConfigProvider")

function GameService.Init(self: GameService, serviceBag: ServiceBag.ServiceBag)
	serviceBag:GetService(MantleConfigProvider.new(script.MantleConfigs))
end
```

`LoadConfigData(data, configName)` is also available when the Mantle table is
already loaded by another build system.

## Cmdr integration

Loading the server and client services registers Cmdr argument types such as
`badgeId`, `badgeIds`, `productId`, `passId`, and `placeId`. Configured keys are
fuzzy-matched, autocompleted, and parsed into their underlying IDs. The friendlier
aliases `product`, `products`, `gamepass`, `gamepasses`, `place`, and `places` are
also available; the plural forms accept comma-separated values. Raw numeric IDs
remain valid.

Two server commands are included:

- `give-badge`
- `goto-place` (alias: `goto-named-place`)

The client also uses the active configuration name as Cmdr's displayed place
name.
