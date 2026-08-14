# ServerRegionService

`ServerRegionService` performs one server-side IP-geolocation request and writes
the resulting `"Region, CC"` string to the `ServerRegion` attribute on
`ReplicatedStorage`. Roblox then replicates the attribute without a custom
network packet.

HTTP requests must be enabled for the experience. IP geolocation is approximate,
depends on the configured third-party endpoint, and can identify an outbound
proxy rather than the physical Roblox host. A failed request is warned and leaves
the attribute unset.

## Server

```luau
const serverRegionService = serviceBag:GetService(require("@game/ServerStorage/ServerPackages/ServerRegionService"))

serverRegionService:PromiseRegion():Then(function(region)
	print(`Running in {region}`)
end)
```

## Client

```luau
const serverRegionServiceClient = serviceBag:GetService(require("@game/ReplicatedStorage/Packages/ServerRegionServiceClient"))

serverRegionServiceClient:PromiseRegion():Then(function(region)
	print(`Connected to {region}`)
end)
```

`GetRegion()` is also available on both realms and returns `nil` until the
attribute exists. `PromiseRegion()` waits for a valid replicated attribute.
