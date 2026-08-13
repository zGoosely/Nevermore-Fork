--!strict
--[=[
	Captures server errors and delivers bounded batches to a Discord webhook.

	@class ErrorReportingService
	@server
]=]

const HttpService = game:GetService("HttpService")
const LogService = game:GetService("LogService")
const Aggregator = require("@game/ReplicatedStorage/Packages/Aggregator")
const ErrorReportingUtils = require("./ErrorReportingUtils")
const HttpPromise = require("@game/ReplicatedStorage/Packages/HttpPromise")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const PromiseRetryUtils = require("@game/ReplicatedStorage/Packages/PromiseRetryUtils")
const SecretService = require("@game/ReplicatedStorage/Packages/SecretService")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")
const WebhookUtils = require("@game/ReplicatedStorage/Packages/WebhookUtils")

const DEFAULT_ENDPOINT_SECRET_KEY = "ErrorReportingEndpoint"
const MAX_BATCH_SIZE = 2
const MAX_PENDING_REPORTS = 100

type Endpoint = string | Secret
type ErrorReport = ErrorReportingUtils.ErrorReport
type BatchResult = {
	Id: number,
}
type RequestHeaders = { [string]: string | Secret }

const ErrorReportingService = {}
ErrorReportingService.ServiceName = "ErrorReportingService"
ErrorReportingService.ServerOnly = true

export type ErrorReportingService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_secretService: SecretService.SecretService,
		_endpointPromise: Promise.Promise<()>,

		_endpoint: Endpoint?,
		_endpointSecretKey: string,
		_endpointWasSetManually: boolean,

		_authenticationSecretKey: string?,
		_aggregator: Aggregator.Aggregator<BatchResult>,
		_reportsById: { [number]: ErrorReport },
		_submittedReportIds: { [number]: boolean },
		_nextRequestId: number,
		_pendingReportCount: number,
	},
	{} :: typeof({ __index = ErrorReportingService })
))

function ErrorReportingService.Init(self: ErrorReportingService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._secretService = self._serviceBag:GetService(SecretService)

	self._endpointPromise = self._maid:Add(Promise.new())
	self._endpoint = nil
	self._endpointSecretKey = DEFAULT_ENDPOINT_SECRET_KEY
	self._endpointWasSetManually = false

	self._authenticationSecretKey = nil
	self._reportsById = {}
	self._submittedReportIds = {}
	self._nextRequestId = 0
	self._pendingReportCount = 0

	self._aggregator = self._maid:Add(Aggregator.new("ErrorReportingService.sendReports", function(reportIds)
		return self:_promiseSendReports(reportIds)
	end))

	self._aggregator:SetMaxBatchSize(MAX_BATCH_SIZE)

	self._maid:Add(LogService.MessageOut:Connect(function(message, messageType, context)
		if messageType ~= Enum.MessageType.MessageError then
			return
		end

		const success, reportOrError = pcall(function()
			return ErrorReportingUtils.createReport(message, messageType, context)
		end)
		if not success then
			warn(`[ErrorReportingService] Failed to create an error report: {reportOrError}`)
			return
		end

		self:_enqueueReport(reportOrError :: ErrorReport)
	end))
end

function ErrorReportingService.Start(self: ErrorReportingService): ()
	if not self._endpointWasSetManually then
		self:_loadEndpoint()
	end

	self._maid:GivePromise(self._endpointPromise:Then(function()
		self:_submitPendingReports()
	end))
end

--[=[
	Sets the Discord webhook endpoint directly. Prefer configuring a webhook URL
	secret for production deployments.

	@within ErrorReportingService
	@param endpoint string
	@return ()
]=]
function ErrorReportingService.SetEndpoint(self: ErrorReportingService, endpoint: string): ()
	assert(t.string(endpoint) and string.match(endpoint, "^https://") ~= nil, "Bad HTTPS endpoint")

	self._endpoint = endpoint
	self._endpointWasSetManually = true
	self._endpointPromise:Resolve()
end

--[=[
	Sets the SecretService key containing the Discord webhook URL.

	@within ErrorReportingService
	@param secretKey string
	@return ()
]=]
function ErrorReportingService.SetEndpointSecretKey(self: ErrorReportingService, secretKey: string): ()
	assert(t.string(secretKey) and secretKey ~= "", "Bad secretKey")

	self._endpointSecretKey = secretKey
	self._endpointWasSetManually = false
	self._endpoint = nil
end

--[=[
	Configures the SecretService key used for the request authentication header.

	@within ErrorReportingService
	@param secretKey string
	@return ()
]=]
function ErrorReportingService.SetAuthenticationSecretKey(self: ErrorReportingService, secretKey: string): ()
	assert(t.string(secretKey) and secretKey ~= "", "Bad secretKey")

	self._authenticationSecretKey = secretKey
end

function ErrorReportingService._loadEndpoint(self: ErrorReportingService): ()
	const endpointSecretKey = self._endpointSecretKey
	self._maid:GivePromise(self._secretService
		:PromiseSecret(endpointSecretKey)
		:Then(function(endpoint)
			if self._endpointWasSetManually or self._endpointSecretKey ~= endpointSecretKey then
				return
			end

			if endpoint == nil then
				return Promise.rejected(`Missing endpoint secret {endpointSecretKey}`)
			end

			self._endpoint = endpoint :: Endpoint
			self._endpointPromise:Resolve()
		end)
		:Catch(function(errorMessage)
			warn(`[ErrorReportingService] Failed to load endpoint secret: {errorMessage}`)
		end))
end

function ErrorReportingService._enqueueReport(self: ErrorReportingService, report: ErrorReport): ()
	if self._pendingReportCount >= MAX_PENDING_REPORTS then
		warn("[ErrorReportingService] Too many pending reports; dropping report")
		return
	end

	self._nextRequestId += 1
	const requestId = self._nextRequestId
	self._pendingReportCount += 1
	self._reportsById[requestId] = report
	self:_submitReport(requestId)
end

function ErrorReportingService._submitPendingReports(self: ErrorReportingService): ()
	if not self._endpoint then
		return
	end

	for requestId in self._reportsById do
		self:_submitReport(requestId)
	end
end

function ErrorReportingService._submitReport(self: ErrorReportingService, requestId: number): ()
	if not self._endpoint or self._submittedReportIds[requestId] then
		return
	end

	self._submittedReportIds[requestId] = true
	self._aggregator
		:Promise(requestId)
		:Finally(function()
			self._pendingReportCount -= 1
			self._reportsById[requestId] = nil
			self._submittedReportIds[requestId] = nil
		end)
		:Catch(function(errorMessage)
			warn(`[ErrorReportingService] Failed to send error report: {errorMessage}`)
		end)
end

function ErrorReportingService._promiseSendReports(
	self: ErrorReportingService,
	requestIds: { number }
): Promise.Promise<{ BatchResult }>
	const endpoint = self._endpoint
	if not endpoint then
		return Promise.rejected("Error reporting endpoint is not configured")
	end

	local reports = table.create(#requestIds)
	for index, requestId in requestIds do
		const report = self._reportsById[requestId]
		if not report then
			return Promise.rejected(`Missing error report for ID {requestId}`)
		end

		reports[index] = report
	end

	local function promisePostReports(authenticationSecret: (string | Secret)?): Promise.Promise<any>
		const headers: RequestHeaders = {
			["Content-Type"] = "application/json",
		}
		if authenticationSecret then
			headers["x-error-reporting-token"] = authenticationSecret
		end

		const encodedSuccess, bodyOrError = pcall(function(): string
			const embeds = table.create(#reports)
			for index, report in reports do
				embeds[index] = ErrorReportingUtils.createEmbed(report)
			end

			return HttpService:JSONEncode(WebhookUtils.serializeMessage({
				Embeds = embeds,
			}))
		end)
		if not encodedSuccess then
			return Promise.rejected(`Could not encode error reports: {bodyOrError}`)
		end

		const request: HttpPromise.HTTPRequest = {
			Url = endpoint,
			Method = "POST",
			Headers = headers,
			Body = bodyOrError,
		}

		return PromiseRetryUtils.retry(function()
			return HttpPromise.request(request):Then(function(response)
				if not response.Success then
					return Promise.rejected(response)
				end

				return response
			end)
		end, {
			initialWaitTime = 2,
			maxAttempts = 3,
			printWarning = false,
			shouldRetry = function(error): boolean
				if not HttpPromise.isHttpResponse(error) then
					return true
				end

				return error.StatusCode == 408 or error.StatusCode == 429 or error.StatusCode >= 500
			end,
		})
	end

	local postPromise
	if self._authenticationSecretKey then
		postPromise = self._secretService
			:PromiseSecret(self._authenticationSecretKey)
			:Then(function(authenticationSecret)
				if authenticationSecret == nil then
					return Promise.rejected(`Missing authentication secret {self._authenticationSecretKey}`)
				end

				return promisePostReports(authenticationSecret :: string | Secret)
			end)
	else
		postPromise = promisePostReports(nil)
	end

	return postPromise:Then(function()
		local results = table.create(#requestIds)
		for index, requestId in requestIds do
			results[index] = {
				Id = requestId,
			}
		end
		return results
	end)
end

function ErrorReportingService.Destroy(self: ErrorReportingService): ()
	self._maid:DoCleaning()
	table.clear(self._reportsById)
	table.clear(self._submittedReportIds)
	self._pendingReportCount = 0
end

return ErrorReportingService
