# AvatarCatalogService

`AvatarCatalogService` is a server-authoritative catalog for R6 and R15 body parts and body packages. It can apply
catalog entries directly, replace selected avatar assets automatically, and normalize a built-in list of unusually
small or invisible body parts. Roblox catalog lookups are cached for the server lifetime.

## Setup

Resolve the service from your server's `ServiceBag`. Register game-specific catalog entries and replacement rules from
another service so every game's policy remains outside the package.

```luau
--!strict

const AvatarCatalogService = require("@game/ReplicatedStorage/Packages/AvatarCatalogService")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

const AvatarRulesService = {}
AvatarRulesService.ServiceName = "AvatarRulesService"
AvatarRulesService.ServerOnly = true

export type AvatarRulesService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_avatarCatalogService: AvatarCatalogService.AvatarCatalogService,
	},
	{} :: typeof({ __index = AvatarRulesService })
))

function AvatarRulesService.Init(self: AvatarRulesService, serviceBag: ServiceBag.ServiceBag): ()
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._avatarCatalogService = self._serviceBag:GetService(AvatarCatalogService)
end

function AvatarRulesService.Destroy(self: AvatarRulesService): ()
	self._maid:DoCleaning()
end

return AvatarRulesService
```

`AvatarCatalogService` registers its own `PlayerHumanoidBinder`. Once a player's appearance has loaded, the bound
humanoid automatically receives the active rules. Changing a catalog entry, replacement rule, or unfair-list setting
requests another update for all bound player humanoids. NPC humanoids are not discovered by this binder; use the manual
application APIs for them.

## Body parts

Use `SetBodyPart()` to give an approved body asset a stable game-defined name. Asset IDs must be positive integers, and
an existing name cannot change its rig type or body-part slot.

```luau
const APPROVED_R15_HEAD_ASSET_ID = 123456789 -- Replace with your approved asset.

self._avatarCatalogService:SetBodyPart("ApprovedR15Head", {
	RigType = Enum.HumanoidRigType.R15,
	BodyPart = Enum.BodyPart.Head,
	AssetId = APPROVED_R15_HEAD_ASSET_ID,
})
```

Create an automatic rule by mapping a source asset ID to the named replacement. The replacement definition determines
the rig type and body-part slot, so the same numeric source ID cannot affect an unrelated slot.

```luau
const DISALLOWED_R15_HEAD_ASSET_ID = 987654321

self._avatarCatalogService:SetBodyPartReplacement(DISALLOWED_R15_HEAD_ASSET_ID, "ApprovedR15Head")
```

Single body-part application preserves that part's current color. This includes colors stored on modern
`BodyPartDescription` children, so replacing a dynamic head does not reset the player's skin tone. Complete package
application intentionally keeps its existing color behavior.

Entries and rules can be inspected or removed at runtime:

```luau
const definition = self._avatarCatalogService:GetBodyPart("ApprovedR15Head")
if definition then
	print(definition.AssetId)
end

self._avatarCatalogService:RemoveBodyPartReplacement(
	Enum.HumanoidRigType.R15,
	Enum.BodyPart.Head,
	DISALLOWED_R15_HEAD_ASSET_ID
)
self._avatarCatalogService:RemoveBodyPart("ApprovedR15Head")
```

Removing a body part also removes rules that use it as their replacement. It does not revert characters that were
already changed.

## Packages

A package is a non-empty map of body-part slots to asset IDs. R15 packages may also define all six avatar scale values.
Omit `Scales` for an R6 package.

```luau
self._avatarCatalogService:RegisterPackage("CompetitiveR15", {
	RigType = Enum.HumanoidRigType.R15,
	BodyParts = {
		[Enum.BodyPart.Head] = 111111111,
		[Enum.BodyPart.Torso] = 222222222,
		[Enum.BodyPart.LeftArm] = 333333333,
		[Enum.BodyPart.RightArm] = 444444444,
		[Enum.BodyPart.LeftLeg] = 555555555,
		[Enum.BodyPart.RightLeg] = 666666666,
	},
	Scales = {
		BodyTypeScale = 0,
		DepthScale = 1,
		HeadScale = 1,
		HeightScale = 1,
		ProportionScale = 0,
		WidthScale = 1,
	},
})
```

Automatic package rules compare the body parts listed by the source definition. When they all match, the replacement
package's body parts and optional scales are applied.

```luau
self._avatarCatalogService:RegisterPackage("DisallowedR15", {
	RigType = Enum.HumanoidRigType.R15,
	BodyParts = {
		[Enum.BodyPart.Head] = 777777777,
		[Enum.BodyPart.Torso] = 888888888,
	},
})

self._avatarCatalogService:SetPackageReplacement("DisallowedR15", "CompetitiveR15")
```

Both packages must already exist and use the same rig type. Removing either package also removes automatic package
rules that reference it.

## Loading Roblox bundles and legacy packages

Use `LoadBundleAsync()` for a modern Roblox avatar bundle. It loads the bundle's outfit description, converts it into a
package definition, caches the result, and registers it under the provided name.

```luau
function AvatarRulesService.Start(self: AvatarRulesService): ()
	const promise = self._avatarCatalogService:LoadBundleAsync("GnomskyBrothers", 652, Enum.HumanoidRigType.R15)
		:Then(function(packageDefinition)
			print(`Loaded {packageDefinition.RigType.Name} bundle`)
		end)
		:Catch(function(err)
			warn(`Could not load avatar bundle: {err}`)
		end)
	self._maid:GivePromise(promise)
end
```

Use `LoadPackageAssetAsync()` for a legacy Roblox package asset:

```luau
const promise = self._avatarCatalogService:LoadPackageAssetAsync("LegacyPackage", 123456789, Enum.HumanoidRigType.R6)
	:Then(function()
		self._avatarCatalogService:SetPackageReplacement("LegacyPackage", "ApprovedR6")
	end)
	:Catch(function(err)
		warn(`Could not load legacy package: {err}`)
	end)
self._maid:GivePromise(promise)
```

Concurrent requests for the same catalog identity share one in-flight request, and successful results remain cached for
the server lifetime. Failed requests are evicted so a later call can retry. The returned definitions and values returned
by `GetBodyPart()` or `GetPackage()` are copies; callers cannot mutate the service's stored catalog accidentally.

## Applying entries manually

Manual application changes one humanoid without creating an automatic rule. Both methods return a `Promise<boolean>`;
the boolean is `true` when the humanoid description changed.

```luau
self._avatarCatalogService:ApplyBodyPartAsync(humanoid, "ApprovedR15Head")
	:Then(function(changed)
		print(`Head changed: {changed}`)
	end)

self._avatarCatalogService:ApplyPackageAsync(humanoid, "CompetitiveR15")
	:Catch(function(err)
		warn(`Could not apply package: {err}`)
	end)
```

The entry's rig type must match `humanoid.RigType`. To evaluate every currently configured automatic rule explicitly,
including the built-in unfair list, use:

```luau
self._avatarCatalogService:EnforceAsync(humanoid):Catch(function(err)
	warn(`Could not enforce avatar policy: {err}`)
end)
```

Calls to `EnforceAsync()` for the same humanoid share the active enforcement promise. If policy changes while that
promise is running, the service applies the latest revision before completing.

## Built-in unfair package list

`WellKnownUnfairPackagesAndParts` is enabled by default. It replaces known parts from these Roblox-authored packages
with the rig's default body geometry:

- Headless Horseman heads
- Korblox Deathspeaker right leg
- The Gnomsky Brothers
- Skelly
- Magma Fiend
- Piggy

Disable or re-enable the list at runtime without affecting game-defined rules:

```luau
self._avatarCatalogService:ShouldUseUnfairList(false)
self._avatarCatalogService:ShouldUseUnfairList(true)
```

Disabling the list stops subsequent built-in enforcement but does not reconstruct characters that were already
normalized. Re-enabling it requests an update for all currently bound player humanoids.

The constants can also be inspected without modifying them:

```luau
const WellKnownUnfairPackagesAndParts =
	require("@game/ReplicatedStorage/Packages/WellKnownUnfairPackagesAndParts")

for packageName, packageDefinition in WellKnownUnfairPackagesAndParts.PACKAGES do
	print(packageName, packageDefinition.BundleId)
end
```

The default entries are intentionally limited to stable Roblox-authored identities. Roblox's bundle API identifies
[Headless Horseman](https://catalog.roblox.com/v1/bundles/201/details),
[Korblox Deathspeaker](https://catalog.roblox.com/v1/bundles/192/details),
[The Gnomsky Brothers](https://catalog.roblox.com/v1/bundles/652/details),
[Skelly](https://catalog.roblox.com/v1/bundles/353/details),
[Magma Fiend](https://catalog.roblox.com/v1/bundles/429/details), and
[Piggy](https://catalog.roblox.com/v1/bundles/998/details).
[Roblox's avatar-body specification](https://create.roblox.com/docs/avatar/character-bodies/specifications) requires
opaque, substantially visible body geometry, while competitive developers have
[documented the gameplay problems](https://devforum.roblox.com/t/small-invisible-avatars-wreaking-havoc-on-games/3172363)
caused by small or invisible avatar parts. Static lists cannot keep pace with every UGC combination, so games should add
their own entries with `SetBodyPart()`, `RegisterPackage()`, and the corresponding replacement methods.

## Update observation and Tie integration

`ObserveUpdateRequested()` emits the current numeric revision immediately and emits again whenever policy changes.

```luau
self._maid:Add(self._avatarCatalogService:ObserveUpdateRequested():Subscribe(function(revision)
	print(`Avatar policy revision: {revision}`)
end))
```

Internally, `AvatarCatalogServiceInterface` exposes `ObserveUpdateRequested()` and `EnforceAsync()` through a
server-realm Tie implemented on `ReplicatedStorage`. `AvatarCatalogHumanoid` resolves this interface itself; callers do
not pass service callbacks into the binder class.
