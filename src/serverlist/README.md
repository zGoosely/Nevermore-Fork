# ServerListService

`ServerListService` publishes a bounded place-scoped directory through `MemoryStoreHashMap`. Each game server publishes one expiring entry, while directory reads happen only when at least one local client observes the list. All interested clients in the same server share one cache and refresh operation.

## Configuration

Edit `Shared/ServerListConstants.luau` to configure:

- publish, refresh, and expiration intervals;
- maximum visible servers and MemoryStore pages;
- listed server types;
- request rate limits;
- the recent-server window;
- generated-name descriptors, nouns, and numeric suffixes.

Entries expire automatically after `ENTRY_TTL_SECONDS`. `Rx.interval` owns the fixed publish and refresh schedules.

## Client observation

```luau
const ServerListFilters = require("ServerListFilters")
const ServerListServiceClient = require("ServerListServiceClient")

const serverListServiceClient = serviceBag:GetService(ServerListServiceClient)

maid:Add(serverListServiceClient:ObserveServersByFilters({
	ServerListFilters.new("Recent"),
	ServerListFilters.new("Available"),
	ServerListFilters.new("MostPlayers"),
}):Subscribe(function(servers)
	-- Render the immutable snapshot.
end))
```

Built-in filters are:

- `Recent`: keeps servers started within `RECENT_SERVER_WINDOW_SECONDS`;
- `Available`: removes full servers;
- `NotEmpty`: removes empty servers;
- `Region`: keeps an exact region string, for example `ServerListFilters.new("Region", "Europe")`;
- `MostPlayers` and `LeastPlayers`: select the ordering.

Predicates run before ordering. Without an explicit player-count ordering, results are ordered newest-first. Filters are local and never sent over the network.

`ObserveServers()` is reference-counted. The first observer enables shared directory refreshes and the last observer disables them. Publishing the current server continues regardless, so other servers can discover it.

## Region metadata

Roblox does not expose a reliable physical datacenter region. Region metadata is optional and must identify its source:

```luau
const serverListService = serviceBag:GetService(ServerListService)
serverListService:SetRegion("Europe", "configured")
```

Use `nil, "unknown"` to clear it. The package does not infer a server region from players.

By default, `ServerListService` waits for `ServerRegionService` and publishes its
approximate IP-geolocation result with the `external` source. Calling `SetRegion`
can still replace that value with explicitly configured metadata.

## Joining

```luau
serverListServiceClient:JoinServerAsync(metadata.jobId)
```

The returned promise resolves after the bounded request is queued locally. The server validates its cached metadata, freshness, capacity, place, and server type before requesting the teleport. Roblox may still reject or delay the eventual transition.

## Pagination choice

`PagesUtils`, `PagesDatabase`, and `PagesProxy` are designed to share traversal of one `Pages` cursor among multiple consumers. The registry has one shared consumer and creates a fresh MemoryStore cursor for each refresh, so wrapping it would add allocations without reducing MemoryStore requests. The registry instead traverses pages directly with strict page and result caps.
