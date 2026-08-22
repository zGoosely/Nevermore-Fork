# ChatProviderService

`ChatProviderService` owns ordered, server-authoritative tags for players. The client package renders enabled tags through Roblox's modern `TextChatService` API.

```lua
local ChatProviderService = serviceBag:GetService(require("ChatProviderService"))

local revoke = ChatProviderService:AddTag(player, {
	Id = "admin",
	Text = "ADMIN",
	Order = 1,
	Color = Color3.fromRGB(255, 80, 80),
})

ChatProviderService:SetTagEnabled(player, "admin", false)
revoke()
```

Tags are observed through `ChatProviderServiceInterface` with `ObserveUserTagsByName` and `ObserveUserTagsByNameBrio`.
