# Server data stores

This package provides a small wrapper around Roblox data stores and two services that choose the scope and lifetime of
that wrapper for you.

| Component | Stored scope | Typical use |
| --- | --- | --- |
| `DataStore` | One key in a Roblox `GlobalDataStore` | The shared loading, caching, staging, saving, and syncing API |
| `GameDataStoreService` | One game-wide key shared by every server | Global flags, configuration, and other cross-server state |
| `PrivateServerDataStoreService` | The current private server ID, or `"main"` in a public server | Private or reserved-server session metadata |

All three modules are server-only. For player profiles, use `PlayerDataStoreService` instead.

## Choosing a store

Use `GameDataStoreService` when every live server should see the same data. For example, it can store a maintenance
flag or a game-wide configuration value.

Use `PrivateServerDataStoreService` when data belongs to a particular reserved or private server. This is useful for
soft-shutdown waiting servers because the source server can write to the destination private-server ID before players
arrive.

Use `DataStore` directly only when a package needs to own a separate Roblox data-store name, scope, and key. Most
services should use one of the two existing services instead.

## Using `DataStore`

A `DataStore` represents one Roblox data-store key. Its contents are a table whose top-level entries are addressed by
`Load` and `Store`.

```luau
dataStore:Load("MaintenanceEnabled", false):Then(function(isEnabled)
	print(isEnabled)
end)

dataStore:Store("MaintenanceEnabled", true)

dataStore:Save():Catch(function(err)
	warn("Failed to save game data", err)
end)
```

`Store` only stages a local change. Call `Save` when an important write must be sent immediately instead of waiting for
the configured autosave.

The main operations are:

- `Load(key, defaultValue)` loads one top-level value. Once the store has loaded, later calls read its local snapshot.
- `LoadAll(defaultValue)` loads a copy of the complete stored table.
- `Store(key, value)` stages a value for the next save. Passing `nil` deletes that key.
- `Save()` atomically applies staged top-level changes with `UpdateAsync`.
- `Sync()` refreshes the local snapshot from Roblox without discarding pending local changes.
- `SetAutoSaveTimeSeconds(seconds)` changes the autosave interval. Passing `nil` disables autosaving.
- `SetSyncOnSave(enabled)` makes a save with no pending changes refresh from Roblox.
- `DidLoadFail()` reports whether the most recent load attempt failed.
- `GetKey()` returns the wrapped Roblox data-store key.

Loaded and stored tables are copied, so mutating a returned table does not stage another write. Call `Store` again after
changing a table.

Concurrent servers can safely update different top-level entries because saves use `UpdateAsync`. If multiple servers
write the same entry, application-level conflict rules may still be needed.

## Using `GameDataStoreService`

Resolve the service in `Init`, then request its `DataStore`. By default it uses the Roblox data store
`GameDataStore` with scope `Version1` and key `version1`.

```luau
--!strict
const GameDataStoreService = require("@game/ReplicatedStorage/Packages/GameDataStoreService")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

type ExampleService = {
	_gameDataStoreService: GameDataStoreService.GameDataStoreService,
}

local ExampleService = {}

function ExampleService.Init(self: ExampleService, serviceBag: ServiceBag.ServiceBag): ()
	self._gameDataStoreService = serviceBag:GetService(GameDataStoreService)
end

function ExampleService.Start(self: ExampleService): ()
	self._gameDataStoreService
		:PromiseDataStore()
		:Then(function(dataStore)
			return dataStore:Load("MaintenanceEnabled", false)
		end)
		:Then(function(isEnabled)
			print("Maintenance enabled:", isEnabled)
		end)
		:Catch(function(err)
			warn("Failed to load game data", err)
		end)
end
```

To write game-wide data:

```luau
self._gameDataStoreService
	:PromiseDataStore()
	:Then(function(dataStore)
		dataStore:Store("MaintenanceEnabled", true)
		return dataStore:Save()
	end)
	:Catch(function(err)
		warn("Failed to save game data", err)
	end)
```

`SetDataStoreKey(key)` can select a different key, but it must be called before the service's first
`PromiseDataStore()` call. `SetRobloxDataStore(robloxDataStore)` is available for dependency injection and must also be
configured before the first request.

The service enables syncing on empty saves, configures a five-second autosave, saves during shutdown, and owns the
returned `DataStore` lifecycle.

## Using `PrivateServerDataStoreService`

Resolve this service in `Init` in the same way as `GameDataStoreService`.

`PromiseDataStore()` selects:

- `game.PrivateServerId` while running in a private or reserved server;
- `"main"` while running in a public server; or
- the key supplied to `SetCustomKey(key)`.

The default backing Roblox data store is `PrivateServerDataStores` with scope `Version1`.

Read or write data for the current server:

```luau
self._privateServerDataStoreService
	:PromiseDataStore()
	:Then(function(dataStore)
		return dataStore:Load("IsSoftShutdownLobby", false)
	end)
	:Then(function(isSoftShutdownLobby)
		if isSoftShutdownLobby then
			print("Players should wait here without loading player profiles")
		end
	end)
	:Catch(function(err)
		warn("Failed to load private-server data", err)
	end)
```

Write data for a destination reserved server before teleporting players:

```luau
self._privateServerDataStoreService
	:PromiseDataStoreForKey(teleportResult.PrivateServerId)
	:Then(function(dataStore)
		dataStore:Store("IsSoftShutdownLobby", true)
		return dataStore:Save()
	end)
	:Then(function()
		-- Teleport only after the destination marker has been persisted.
	end)
	:Catch(function(err)
		warn("Failed to prepare the soft-shutdown server", err)
	end)
```

`PromiseDataStoreForKey(key)` is the preferred API when the target private-server ID is already known.
`SetCustomKey(key)` changes what `PromiseDataStore()` selects and must be called before its first request.
`SetRobloxDataStore(robloxDataStore)` is available for dependency injection before any store is requested.

All public servers use the same `"main"` key. It is not unique to a public server process, so do not use it as
per-`JobId` storage.

This service uses `DataStore`'s default five-minute autosave, saves its stores during shutdown, and owns their
lifecycle.

## Constructing `DataStore` directly

When a package genuinely needs a separate backing store, pass a Roblox `GlobalDataStore` and one key to `DataStore.new`.
The owning class or service must also clean it up.

```luau
const RobloxDataStoreService = game:GetService("DataStoreService")
const DataStore = require("@game/ReplicatedStorage/Packages/DataStore")

const robloxDataStore = RobloxDataStoreService:GetDataStore("RoundHistory", "Version1")
const roundHistory = DataStore.new(robloxDataStore, "current")

roundHistory:SetAutoSaveTimeSeconds(300)
```

Register a directly constructed store with the owner's `Maid`, or call `Destroy()` when its lifetime ends.

## Reliability notes

- Always handle a rejected `Load`, `Save`, or `Sync` promise.
- Await `Save()` before relying on a value in another server, especially before teleporting players.
- A normal `Load` uses the wrapper's cached snapshot after the initial request; use `Sync` when a fresh remote snapshot
  is required.
- Service-owned stores are saved during shutdown, but explicit saves are still appropriate at important handoff
  boundaries.
- These stores are not a replacement for `PlayerDataStoreService` and should not cause player profiles to load in a
  soft-shutdown waiting server.
