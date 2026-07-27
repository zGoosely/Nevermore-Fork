# PlayerDataStoreService

`PlayerDataStoreService` owns server-side ProfileStore sessions.
`PlayerDataStoreServiceClient` is its read-only client mirror.

The former generic player-data module names have been replaced by their
`PlayerDataStoreService*` equivalents.

Before observing players, the server checks `PrivateServerDataStoreService` for
the soft-shutdown lobby marker. A waiting server never opens ProfileStore
sessions. Teleport metadata is checked again for each player as a second guard.

When a full waiting server returns to a live server, profile starts are limited
to five concurrent operations with `AsyncSemaphore`; the remaining players wait
in FIFO order.
