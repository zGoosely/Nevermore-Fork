# ErrorReportingService

`ErrorReportingService` observes server error output, enriches it with
experience and server metadata, and posts bounded batches of Discord embeds.
The Discord webhook URL is loaded from `SecretService` using the
`ErrorReportingEndpoint` key by default.

Register the service in the server `ServiceBag`, configure the endpoint during
application initialization before calling `serviceBag:Start()`, and optionally
configure a Roblox Secret for the authentication header:

```luau
local ErrorReportingService = require("@game/ServerStorage/ServerPackages/ErrorReportingService")
local ErrorReportingUtils = require("@game/ServerStorage/ServerPackages/ErrorReportingUtils")

local errorReportingService = serviceBag:GetService(ErrorReportingService)
errorReportingService:SetEndpointSecretKey("ErrorReportingEndpoint")
errorReportingService:SetAuthenticationSecretKey("ErrorReportingToken")

ErrorReportingUtils.logFatal("Failed to initialize the match", {
	matchId = matchId,
})
```

Each report becomes one Discord embed containing a referenceable report ID,
message, stack, context, place metadata, player count, realm, and Studio status.
Timestamps include both UTC text and Discord's live relative-time display. Up to
two reports are sent per webhook request to stay within Discord's combined embed
limit.
