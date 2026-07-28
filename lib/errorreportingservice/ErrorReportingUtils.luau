--!strict
--[=[
	Creates structured error reports and emits fatal errors for
	ErrorReportingService to observe.

	@util ErrorReportingUtils
	@server
]=]

const HttpService = game:GetService("HttpService")
const LogService = game:GetService("LogService")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const require = require("../Loader").load()

const t = require("t")
const WebhookTypes = require("WebhookTypes")

const FATAL_PREFIX = "[Fatal] "
const MAX_CONTEXT_DEPTH = 4
const MAX_CONTEXT_ENTRIES = 64
const MAX_EMBED_DESCRIPTION_LENGTH = 1000
const MAX_EMBED_FIELD_LENGTH = 512

type ErrorContext = { [string]: any }

export type ErrorReport = {
	schemaVersion: number,
	severity: "error" | "fatal",
	message: string,
	messageType: string,
	stack: string?,
	context: ErrorContext,
	timestamp: number,
	universeId: number,
	placeId: number,
	placeVersion: number,
	jobId: string,
	playerCount: number,
	realm: string,
	isStudio: boolean,
}

local ErrorReportingUtils = {}

local function truncate(value: string, maxLength: number): string
	if #value <= maxLength then
		return value
	end

	return `{string.sub(value, 1, maxLength - 3)}...`
end

local function sanitizeValue(value: any, depth: number, seen: { [any]: boolean }): any
	if value == nil or t.string(value) or t.boolean(value) then
		return value
	end

	if t.number(value) then
		if value == value and value ~= math.huge and value ~= -math.huge then
			return value
		end

		return tostring(value)
	end

	if not t.table(value) then
		return tostring(value)
	end

	if depth >= MAX_CONTEXT_DEPTH then
		return "<maximum context depth>"
	end

	if seen[value] then
		return "<cyclic context>"
	end

	seen[value] = true
	local result = {}
	local entryCount = 0

	for key, nestedValue in value do
		entryCount += 1
		if entryCount > MAX_CONTEXT_ENTRIES then
			break
		end

		const normalizedKey = if t.string(key) then key else tostring(key)
		result[normalizedKey] = sanitizeValue(nestedValue, depth + 1, seen)
	end

	seen[value] = nil
	return result
end

--[=[
	Converts arbitrary context values into a bounded JSON-safe dictionary.

	@within ErrorReportingUtils
	@param context { [string]: any }
	@return { [string]: any }
]=]
function ErrorReportingUtils.sanitizeContext(context: { [string]: any }): ErrorContext
	assert(t.table(context), "Bad context")
	return sanitizeValue(context, 0, {}) :: ErrorContext
end

--[=[
	Creates a report enriched with the current experience and server metadata.

	@within ErrorReportingUtils
	@param message string
	@param messageType Enum.MessageType
	@param context { [string]: any }?
	@return ErrorReport
]=]
function ErrorReportingUtils.createReport(
	message: string,
	messageType: Enum.MessageType,
	context: { [string]: any }?
): ErrorReport
	assert(t.string(message) and message ~= "", "Bad message")
	assert(t.enum(Enum.MessageType)(messageType), "Bad messageType")

	const safeContext = ErrorReportingUtils.sanitizeContext(context or {})
	const hasFatalContext = safeContext.fatal == true
	const hasFatalPrefix = string.sub(message, 1, #FATAL_PREFIX) == FATAL_PREFIX
	const isFatal = hasFatalContext or hasFatalPrefix
	const normalizedMessage = if hasFatalPrefix then string.sub(message, #FATAL_PREFIX + 1) else message
	const stack = if t.string(safeContext.stack) then safeContext.stack else nil

	safeContext.fatal = nil
	safeContext.stack = nil

	return {
		schemaVersion = 1,
		severity = if isFatal then "fatal" else "error",
		message = normalizedMessage,
		messageType = tostring(messageType),
		stack = stack,
		context = safeContext,
		timestamp = os.time(),
		universeId = game.GameId,
		placeId = game.PlaceId,
		placeVersion = game.PlaceVersion,
		jobId = game.JobId,
		playerCount = Players.NumPlayers,
		realm = if RunService:IsServer() then "server" else "client",
		isStudio = RunService:IsStudio(),
	}
end

--[=[
	Converts an enriched report into a Discord webhook embed.

	@within ErrorReportingUtils
	@param report ErrorReport
	@return Embed
]=]
function ErrorReportingUtils.createEmbed(report: ErrorReport): WebhookTypes.Embed
	assert(t.table(report), "Bad report")

	const contextSuccess, contextJson = pcall(function(): string
		return HttpService:JSONEncode(report.context)
	end)
	const contextText = if contextSuccess then contextJson else "<context unavailable>"
	const stackText = report.stack or "<stack unavailable>"
	const metadataText = table.concat({
		`Severity: {report.severity}`,
		`Message Type: {report.messageType}`,
		`Universe: {report.universeId}`,
		`Place: {report.placeId}`,
		`Place Version: {report.placeVersion}`,
		`Job ID: {if report.jobId ~= "" then report.jobId else "<not available>"}`,
		`Players: {report.playerCount}`,
		`Realm: {report.realm}`,
		`Studio: {tostring(report.isStudio)}`,
	}, "\n")
	const fields: { WebhookTypes.EmbedField } = {
		{
			Name = "Metadata",
			Value = truncate(metadataText, MAX_EMBED_FIELD_LENGTH),
		},
		{
			Name = "Context",
			Value = truncate(contextText, MAX_EMBED_FIELD_LENGTH),
		},
	}

	return {
		Title = truncate(`[{string.upper(report.severity)}] {report.message}`, 256),
		Description = truncate(stackText, MAX_EMBED_DESCRIPTION_LENGTH),
		Timestamp = DateTime.fromUnixTimestamp(report.timestamp),
		Color = if report.severity == "fatal" then Color3.fromRGB(220, 50, 50) else Color3.fromRGB(240, 160, 40),
		Fields = fields,
	}
end

--[=[
	Emits a fatal error with a captured call stack. ErrorReportingService observes
	the resulting error output and sends the enriched report to its endpoint.

	@within ErrorReportingUtils
	@param message string
	@param context { [string]: any }?
	@return ()
]=]
function ErrorReportingUtils.logFatal(message: string, context: { [string]: any }?): ()
	assert(t.string(message) and message ~= "", "Bad message")
	assert(t.optional(t.table)(context), "Bad context")

	const safeContext = ErrorReportingUtils.sanitizeContext(context or {})
	safeContext.fatal = true
	safeContext.stack = debug.traceback(nil, 2)

	local escapedMessage = string.gsub(message, "{", "{{")
	escapedMessage = string.gsub(escapedMessage, "}", "}}")
	LogService:Error(`{FATAL_PREFIX}{escapedMessage}`, safeContext)
end

return ErrorReportingUtils
