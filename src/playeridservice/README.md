# PlayerIdService

Assigns every current player a unique replicated `uint8` ID. Automatic IDs use
the compact `1..Players.MaxPlayers` range, remain stable for the player's
session, and are recycled after departure. Zero is intentionally left available
as an unassigned network sentinel.

The realm-aware `PlayerIdServiceInterface` is implemented on `Players`:

- Shared: `GetId(player)`, `ObserveId(player)`
- Server: `RefreshIds()`, `SetIds(assignments)`

Both concrete services also expose `:Observe(player)` as a convenience alias.
Observation is backed by `RxAttributeUtils` and emits `nil` while unassigned.

```luau
local playerIds = serviceBag:GetService(require("PlayerIdService"))

maid:Add(playerIds:Observe(player):Subscribe(function(playerId)
	print(player, playerId)
end))

-- The requested ID wins. Any player currently using 7 is moved automatically.
playerIds:SetIds({
	[player] = 7,
})
```

Code that should discover the capability through Tie can use the realm facade:

```luau
local Players = game:GetService("Players")
local PlayerIdServiceInterface = require("PlayerIdServiceInterface")

local playerIds = PlayerIdServiceInterface.Server:Get(Players) -- server
playerIds:RefreshIds()

local sharedPlayerIds = PlayerIdServiceInterface.Client:Get(Players) -- client
sharedPlayerIds:ObserveId(player):Subscribe(print)
```
