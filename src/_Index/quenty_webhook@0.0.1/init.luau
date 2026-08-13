--!strict
--[=[
	Provides the Promise-first outbound webhook client and payload utilities.

	@class Webhook
	@server
]=]
const WebhookClient = require("./WebhookClient")
const WebhookTypes = require("./WebhookTypes")
const WebhookUtils = require("./WebhookUtils")

return {
	WebhookClient = WebhookClient,
	WebhookTypes = WebhookTypes,
	WebhookUtils = WebhookUtils,
}
