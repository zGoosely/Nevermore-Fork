# Voyager

Voyager provides a Promise-first, outbound Discord webhook client.

```lua
local WebhookClient = require("@game/ServerStorage/ServerPackages/WebhookClient")

local webhookClient = WebhookClient.new(serviceBag, {
	WebhookUrlSecretKey = "DiscordWebhookUrl",
})

webhookClient:SendMessageAsync({
	Content = "Server started",
})
```

The webhook URL is resolved through `SecretService`. Requests are serialized per client, bounded by
`MaxPendingRequests`, and retried for transient HTTP failures. The proxy is enabled by default; set
`UseProxy = false` to send directly to Discord.
