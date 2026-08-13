--!strict
--[=[
	Provides the Promise-first outbound webhook client and payload utilities.

	@class Webhook
	@server
]=]
const WebhookClient = require("@self/WebhookClient")
const WebhookTypes = require("@self/WebhookTypes")
const WebhookUtils = require("@self/WebhookUtils")

return {
	WebhookClient = WebhookClient,
	WebhookTypes = WebhookTypes,
	WebhookUtils = WebhookUtils,
}
