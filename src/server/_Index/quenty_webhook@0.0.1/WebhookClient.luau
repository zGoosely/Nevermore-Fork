--!strict
--[=[
	Sends serialized Discord webhook payloads through a bounded, rate-limit-aware
	Promise queue.

	@class WebhookClient
	@server
]=]

const HttpService = game:GetService("HttpService")
const HttpPromise = require("@game/ServerStorage/ServerPackages/HttpPromise")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const PromiseRetryUtils = require("@game/ReplicatedStorage/Packages/PromiseRetryUtils")
const PromiseUtils = require("@game/ReplicatedStorage/Packages/PromiseUtils")
const SecretService = require("@game/ServerStorage/ServerPackages/SecretService")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")
const WebhookTypes = require("./WebhookTypes")
const WebhookUtils = require("./WebhookUtils")

const DEFAULT_MAX_PENDING_REQUESTS = 100

type RequestSpec = {
	Method: "POST" | "PATCH" | "DELETE",
	Path: string,
	Body: { [string]: any }?,
}

const isClientOptions = t.strictInterface({
	WebhookUrlSecretKey = t.string,
	ProxyUrl = t.optional(t.string),
	UseProxy = t.optional(t.boolean),
	UseProxyQueue = t.optional(t.boolean),
	MaxPendingRequests = t.optional(t.number),
})

local WebhookClient = {}
WebhookClient.ClassName = "WebhookClient"
WebhookClient.__index = WebhookClient

export type WebhookClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_secretService: SecretService.SecretService,
		_baseUrlPromise: Promise.Promise<string>,
		_requestChain: Promise.Promise<()>,
		_useProxy: boolean,
		_useProxyQueue: boolean,
		_maxPendingRequests: number,
		_pendingRequestCount: number,
		_nextRequestAt: number,
	},
	{} :: typeof({ __index = WebhookClient })
))

function WebhookClient.new(serviceBag: ServiceBag.ServiceBag, options: WebhookTypes.WebhookClientOptions): WebhookClient
	assert(t.table(serviceBag), "Bad serviceBag")
	assert(isClientOptions(options), "Bad options")

	const maxPendingRequests = options.MaxPendingRequests or DEFAULT_MAX_PENDING_REQUESTS
	assert(
		maxPendingRequests >= 1 and maxPendingRequests % 1 == 0 and maxPendingRequests <= 1000,
		"Bad options.MaxPendingRequests"
	)

	const self = setmetatable({}, WebhookClient) :: WebhookClient
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	self._maid = Maid.new()
	self._secretService = serviceBag:GetService(SecretService)

	self._useProxy = options.UseProxy ~= false
	self._useProxyQueue = options.UseProxyQueue ~= false
	self._maxPendingRequests = maxPendingRequests
	self._pendingRequestCount = 0
	self._nextRequestAt = 0
	self._requestChain = Promise.resolved()

	self._baseUrlPromise =
		self._maid:GivePromise(self._secretService:PromiseSecret(options.WebhookUrlSecretKey):Then(function(webhookUrl)
			assert(t.string(webhookUrl), "Webhook URL secret must contain a string")
			return WebhookUtils.resolveBaseUrl(webhookUrl, self._useProxy, options.ProxyUrl)
		end))

	return self
end

--[=[
	Sends a webhook message.

	@within WebhookClient
	@param options MessageOptions
	@return Promise<WebhookResponse>
]=]
function WebhookClient.SendMessageAsync(
	self: WebhookClient,
	options: WebhookTypes.MessageOptions
): Promise.Promise<HttpPromise.HTTPResponse>
	return self:_enqueueRequest({
		Method = "POST",
		Path = self:_getSendPath(options.WaitForMessage == true),
		Body = WebhookUtils.serializeMessage(options),
	})
end

--[=[
	Sends a webhook message to a thread.

	@within WebhookClient
	@param threadId string
	@param options MessageOptions
	@return Promise<WebhookResponse>
]=]
function WebhookClient.SendMessageInThreadAsync(
	self: WebhookClient,
	threadId: string,
	options: WebhookTypes.MessageOptions
): Promise.Promise<HttpPromise.HTTPResponse>
	assert(t.string(threadId) and threadId ~= "", "Bad threadId")

	return self:_enqueueRequest({
		Method = "POST",
		Path = `{self:_getSendPath(options.WaitForMessage == true)}&thread_id={threadId}`,
		Body = WebhookUtils.serializeMessage(options),
	})
end

--[=[
	Edits an existing webhook message.

	@within WebhookClient
	@param messageId string
	@param options MessageOptions
	@return Promise<WebhookResponse>
]=]
function WebhookClient.EditMessageAsync(
	self: WebhookClient,
	messageId: string,
	options: WebhookTypes.MessageOptions
): Promise.Promise<HttpPromise.HTTPResponse>
	assert(t.string(messageId) and messageId ~= "", "Bad messageId")

	return self:_enqueueRequest({
		Method = "PATCH",
		Path = `/messages/{messageId}`,
		Body = WebhookUtils.serializeMessage(options),
	})
end

--[=[
	Edits an existing message in a thread.

	@within WebhookClient
	@param threadId string
	@param messageId string
	@param options MessageOptions
	@return Promise<WebhookResponse>
]=]
function WebhookClient.EditMessageInThreadAsync(
	self: WebhookClient,
	threadId: string,
	messageId: string,
	options: WebhookTypes.MessageOptions
): Promise.Promise<HttpPromise.HTTPResponse>
	assert(t.string(threadId) and threadId ~= "", "Bad threadId")
	assert(t.string(messageId) and messageId ~= "", "Bad messageId")

	return self:_enqueueRequest({
		Method = "PATCH",
		Path = `/messages/{messageId}?thread_id={threadId}`,
		Body = WebhookUtils.serializeMessage(options),
	})
end

--[=[
	Deletes an existing webhook message.

	@within WebhookClient
	@param messageId string
	@return Promise<WebhookResponse>
]=]
function WebhookClient.DeleteMessageAsync(
	self: WebhookClient,
	messageId: string
): Promise.Promise<HttpPromise.HTTPResponse>
	assert(t.string(messageId) and messageId ~= "", "Bad messageId")

	return self:_enqueueRequest({
		Method = "DELETE",
		Path = `/messages/{messageId}`,
	})
end

--[=[
	Deletes a message in a thread.

	@within WebhookClient
	@param threadId string
	@param messageId string
	@return Promise<WebhookResponse>
]=]
function WebhookClient.DeleteMessageInThreadAsync(
	self: WebhookClient,
	threadId: string,
	messageId: string
): Promise.Promise<HttpPromise.HTTPResponse>
	assert(t.string(threadId) and threadId ~= "", "Bad threadId")
	assert(t.string(messageId) and messageId ~= "", "Bad messageId")

	return self:_enqueueRequest({
		Method = "DELETE",
		Path = `/messages/{messageId}?thread_id={threadId}`,
	})
end

function WebhookClient._getSendPath(self: WebhookClient, waitForMessage: boolean): string
	const queuePath = if self._useProxy and self._useProxyQueue then "/queue" else ""
	return `{queuePath}?wait={tostring(waitForMessage)}`
end

function WebhookClient._enqueueRequest(
	self: WebhookClient,
	spec: RequestSpec
): Promise.Promise<HttpPromise.HTTPResponse>
	if self._pendingRequestCount >= self._maxPendingRequests then
		return Promise.rejected("Webhook request queue is full")
	end

	self._pendingRequestCount += 1
	const requestPromise = self._requestChain:Then(function()
		return self:_performRequest(spec)
	end, function()
		return self:_performRequest(spec)
	end)

	self._requestChain = requestPromise:Then(function()
		return
	end, function()
		return
	end)

	const resultPromise = requestPromise:Finally(function()
		self._pendingRequestCount -= 1
	end)
	return self._maid:GivePromise(resultPromise)
end

function WebhookClient._performRequest(
	self: WebhookClient,
	spec: RequestSpec
): Promise.Promise<HttpPromise.HTTPResponse>
	return self._baseUrlPromise:Then(function(baseUrl)
		return self:_promiseRequestWithRetry({
			Url = `{baseUrl}{spec.Path}`,
			Method = spec.Method,
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = if spec.Body then HttpService:JSONEncode(spec.Body) else nil,
		})
	end)
end

function WebhookClient._promiseRequestWithRetry(
	self: WebhookClient,
	request: HttpPromise.HTTPRequest
): Promise.Promise<HttpPromise.HTTPResponse>
	return PromiseRetryUtils.retry(function()
		const waitTime = math.max(self._nextRequestAt - os.clock(), 0)

		return PromiseUtils.delayed(waitTime):Then(function()
			return HttpPromise.request(request):Then(function(response)
				self:_observeRateLimit(response)
				return response
			end, function(errorValue)
				if HttpPromise.isHttpResponse(errorValue) then
					self:_observeRateLimit(errorValue :: HttpPromise.HTTPResponse)
				end
				return Promise.rejected(errorValue)
			end)
		end)
	end, {
		initialWaitTime = 1,
		maxAttempts = 3,
		printWarning = false,
		shouldRetry = WebhookUtils.isTransientFailure,
	})
end

function WebhookClient._observeRateLimit(self: WebhookClient, response: HttpPromise.HTTPResponse): ()
	local remaining = tonumber(response.Headers["x-ratelimit-remaining"])
	const shouldWaitForBucket = response.StatusCode == 429 or (remaining ~= nil and remaining <= 0)
	if not shouldWaitForBucket then
		return
	end

	const retryAfter = WebhookUtils.getRetryAfterSeconds(response, self._useProxy)
	if retryAfter then
		self._nextRequestAt = math.max(self._nextRequestAt, os.clock() + retryAfter)
	end
end

function WebhookClient.Destroy(self: WebhookClient): ()
	self._maid:DoCleaning()
end

return WebhookClient
