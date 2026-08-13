# PlayerMock

`PlayerMock` is an in-memory `Folder` marked with the `PlayerMock` CollectionService tag. It lets tests
exercise code that expects a `Player` without trying to construct Roblox's non-constructible `Player`
class.

```luau
const PlayerMock = require("@game/ReplicatedStorage/Packages/PlayerMock")

local player = PlayerMock.new({
	UserId = 12345,
	AccountAge = 30,
})
player.Parent = game:GetService("Players")

assert(PlayerMock.isMock(player))
assert(PlayerMock.read(player, "UserId") == 12345)

PlayerMock.writeLookup(player, "MarketplaceService.UserOwnsGamePassAsync", 123, true)
assert(PlayerMock.readLookup(player, "MarketplaceService.UserOwnsGamePassAsync", 123) == true)

player:Destroy()
```

Use `PlayerMock.read` for native Player properties such as `UserId`, `MembershipType`, `Character`, and
`RespawnLocation`. Use `getSignal`/`fireSignal` for test-side event delivery and `loadCharacterAsync` for
character-dependent code.
