--!strict
--[=[
	Validates and serializes outbound Discord webhook payloads.

	@util WebhookUtils
	@server
]=]
const t = require("@game/ReplicatedStorage/Packages/t")
const WebhookTypes = require("./WebhookTypes")

const DEFAULT_PROXY_URL = "https://webhook.lewisakura.moe"

local isEmbedField = t.strictInterface({
	Name = t.string,
	Value = t.string,
	Inline = t.optional(t.boolean),
})

local isEmbedFooter = t.strictInterface({
	Text = t.string,
	IconUrl = t.optional(t.string),
})

local isEmbedImage = t.strictInterface({
	Url = t.string,
})

local isEmbedThumbnail = t.strictInterface({
	Url = t.string,
})

local isEmbedAuthor = t.strictInterface({
	Name = t.string,
	Url = t.optional(t.string),
	IconUrl = t.optional(t.string),
})

local isEmbed = t.strictInterface({
	Title = t.optional(t.string),
	Description = t.optional(t.string),
	Url = t.optional(t.string),
	Timestamp = t.optional(t.typeof("DateTime")),
	Color = t.optional(t.typeof("Color3")),
	Footer = t.optional(isEmbedFooter),
	Image = t.optional(isEmbedImage),
	Thumbnail = t.optional(isEmbedThumbnail),
	Author = t.optional(isEmbedAuthor),
	Fields = t.optional(t.array(isEmbedField)),
})

local isMessageOptions = t.strictInterface({
	Content = t.optional(t.string),
	Embeds = t.optional(t.array(isEmbed)),
	UseTTS = t.optional(t.boolean),
	UsernameOverride = t.optional(t.string),
	AvatarOverride = t.optional(t.string),
	Flags = t.optional(t.number),
	ThreadName = t.optional(t.string),
	WaitForMessage = t.optional(t.boolean),
})

local WebhookUtils = {}

local function isHttpUrl(url: string): boolean
	return string.match(url, "^https?://[^%s]+$") ~= nil
end

local function isHttpsUrl(url: string): boolean
	return string.match(url, "^https://[^%s]+$") ~= nil
end

local function validateEmbed(embed: WebhookTypes.Embed, index: number): ()
	assert(isEmbed(embed), `Bad embeds[{index}]`)

	if embed.Title then
		assert(#embed.Title <= 256, `Embeds[{index}].Title exceeds 256 characters`)
	end
	if embed.Description then
		assert(#embed.Description <= 4096, `Embeds[{index}].Description exceeds 4096 characters`)
	end
	if embed.Url then
		assert(isHttpUrl(embed.Url), `Embeds[{index}].Url must be an HTTP URL`)
	end

	if embed.Footer then
		assert(#embed.Footer.Text <= 2048, `Embeds[{index}].Footer.Text exceeds 2048 characters`)
		if embed.Footer.IconUrl then
			assert(isHttpsUrl(embed.Footer.IconUrl), `Embeds[{index}].Footer.IconUrl must be HTTPS`)
		end
	end

	if embed.Image then
		assert(isHttpsUrl(embed.Image.Url), `Embeds[{index}].Image.Url must be HTTPS`)
	end
	if embed.Thumbnail then
		assert(isHttpsUrl(embed.Thumbnail.Url), `Embeds[{index}].Thumbnail.Url must be HTTPS`)
	end
	if embed.Author then
		assert(#embed.Author.Name <= 256, `Embeds[{index}].Author.Name exceeds 256 characters`)
		if embed.Author.Url then
			assert(isHttpUrl(embed.Author.Url), `Embeds[{index}].Author.Url must be an HTTP URL`)
		end
		if embed.Author.IconUrl then
			assert(isHttpsUrl(embed.Author.IconUrl), `Embeds[{index}].Author.IconUrl must be HTTPS`)
		end
	end

	if embed.Fields then
		assert(#embed.Fields <= 25, `Embeds[{index}].Fields exceeds 25 fields`)
		for fieldIndex, field in embed.Fields do
			assert(#field.Name <= 256, `Embeds[{index}].Fields[{fieldIndex}].Name exceeds 256 characters`)
			assert(#field.Value <= 1024, `Embeds[{index}].Fields[{fieldIndex}].Value exceeds 1024 characters`)
		end
	end
end

local function getEmbedCharacterCount(embed: WebhookTypes.Embed): number
	local count = 0
	if embed.Title then
		count += #embed.Title
	end
	if embed.Description then
		count += #embed.Description
	end
	if embed.Footer then
		count += #embed.Footer.Text
	end
	if embed.Author then
		count += #embed.Author.Name
	end
	if embed.Fields then
		for _, field in embed.Fields do
			count += #field.Name + #field.Value
		end
	end
	return count
end

local function serializeEmbed(embed: WebhookTypes.Embed): { [string]: any }
	local result = {
		title = embed.Title,
		description = embed.Description,
		url = embed.Url,
	}

	if embed.Timestamp then
		result.timestamp = embed.Timestamp:ToIsoDate()
	end
	if embed.Color then
		const red = math.floor(embed.Color.R * 255 + 0.5)
		const green = math.floor(embed.Color.G * 255 + 0.5)
		const blue = math.floor(embed.Color.B * 255 + 0.5)
		result.color = bit32.lshift(red, 16) + bit32.lshift(green, 8) + blue
	end
	if embed.Footer then
		result.footer = {
			text = embed.Footer.Text,
			icon_url = embed.Footer.IconUrl,
		}
	end
	if embed.Image then
		result.image = { url = embed.Image.Url }
	end
	if embed.Thumbnail then
		result.thumbnail = { url = embed.Thumbnail.Url }
	end
	if embed.Author then
		result.author = {
			name = embed.Author.Name,
			url = embed.Author.Url,
			icon_url = embed.Author.IconUrl,
		}
	end
	if embed.Fields then
		result.fields = table.create(#embed.Fields)
		for index, field in embed.Fields do
			result.fields[index] = {
				name = field.Name,
				value = field.Value,
				inline = field.Inline,
			}
		end
	end

	return result
end

--[=[
	Validates a complete outbound message payload.

	@within WebhookUtils
	@param options MessageOptions
	@return ()
]=]
function WebhookUtils.validateMessageOptions(options: WebhookTypes.MessageOptions): ()
	assert(isMessageOptions(options), "Bad message options")
	assert(
		(options.Content ~= nil and options.Content ~= "") or (options.Embeds ~= nil and #options.Embeds > 0),
		"Message requires Content or Embeds"
	)
	if options.Content then
		assert(#options.Content <= 2000, "Content exceeds 2000 characters")
	end

	if options.Embeds then
		assert(#options.Embeds <= 10, "Embeds exceeds 10 entries")

		local totalCharacters = 0
		for index, embed in options.Embeds do
			validateEmbed(embed, index)
			totalCharacters += getEmbedCharacterCount(embed)
		end

		assert(totalCharacters <= 6000, "Combined embed content exceeds 6000 characters")
	end

	if options.UsernameOverride then
		assert(
			#options.UsernameOverride >= 1 and #options.UsernameOverride <= 80,
			"UsernameOverride must be 1-80 characters"
		)
	end

	if options.AvatarOverride then
		assert(isHttpsUrl(options.AvatarOverride), "AvatarOverride must be HTTPS")
	end

	if options.ThreadName then
		assert(#options.ThreadName <= 100, "ThreadName exceeds 100 characters")
	end
end

--[=[
	Serializes a validated message payload to Discord's webhook format.

	@within WebhookUtils
	@param options MessageOptions
	@return { [string]: any }
]=]
function WebhookUtils.serializeMessage(options: WebhookTypes.MessageOptions): { [string]: any }
	WebhookUtils.validateMessageOptions(options)

	local result: { [string]: any } = {
		content = options.Content,
		tts = options.UseTTS,
		username = options.UsernameOverride,
		avatar_url = options.AvatarOverride,
		flags = options.Flags,
		thread_name = options.ThreadName,
	}

	if options.Embeds then
		result.embeds = table.create(#options.Embeds)

		for index, embed in options.Embeds do
			result.embeds[index] = serializeEmbed(embed)
		end
	end
	return result
end

--[=[
	Builds the webhook base URL from a full Discord webhook URL.

	@within WebhookUtils
	@param webhookUrl string
	@param useProxy boolean
	@param proxyUrl string?
	@return string
]=]
function WebhookUtils.resolveBaseUrl(webhookUrl: string, useProxy: boolean, proxyUrl: string?): string
	assert(t.string(webhookUrl) and string.match(webhookUrl, "^https://") ~= nil, "Bad webhookUrl")
	assert(t.boolean(useProxy), "Bad useProxy")
	assert(t.optional(t.string)(proxyUrl), "Bad proxyUrl")

	const webhookId, webhookToken = string.match(webhookUrl, "^https://discord%.com/api/webhooks/([^/]+)/([^/?]+)")
	assert(webhookId and webhookToken, "Webhook URL must be a Discord webhook URL")

	if not useProxy then
		return `https://discord.com/api/webhooks/{webhookId}/{webhookToken}`
	end

	const baseProxyUrl = proxyUrl or DEFAULT_PROXY_URL
	assert(string.match(baseProxyUrl, "^https://[^%s]+$") ~= nil, "Bad proxyUrl")

	return `{string.gsub(baseProxyUrl, "/$", "")}/api/webhooks/{webhookId}/{webhookToken}`
end

--[=[
	Returns the retry delay in seconds represented by a response.

	@within WebhookUtils
	@param response WebhookResponse
	@param isProxy boolean
	@return number?
]=]
function WebhookUtils.getRetryAfterSeconds(response: WebhookTypes.WebhookResponse, isProxy: boolean): number?
	assert(t.table(response), "Bad response")
	assert(t.boolean(isProxy), "Bad isProxy")

	local retryAfter = tonumber(response.Headers["retry-after"] or response.Headers["Retry-After"])
	if retryAfter then
		if isProxy then
			retryAfter /= 1000
		end

		return math.max(retryAfter, 0)
	end

	local resetAfter = tonumber(response.Headers["x-ratelimit-reset-after"])
	if resetAfter then
		return math.max(resetAfter, 0)
	end

	return nil
end

--[=[
	Returns whether an HTTP failure should be retried.

	@within WebhookUtils
	@param value any
	@return boolean
]=]
function WebhookUtils.isTransientFailure(value: any): boolean
	if not t.table(value) then
		return true
	end

	if not t.number(value.StatusCode) then
		return true
	end

	return value.StatusCode == 408 or value.StatusCode == 429 or value.StatusCode >= 500
end

return WebhookUtils
