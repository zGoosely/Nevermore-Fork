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
const MAX_EMBED_FIELD_LENGTH = 512
const MAX_STACK_FRAMES = 10
const FATAL_COLOR = Color3.fromRGB(237, 66, 69)
const ERROR_COLOR = Color3.fromRGB(230, 126, 34)

type ErrorContext = { [string]: any }

export type ErrorReport = {
	reportId: string,
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

local function formatCodeBlock(value: string, maxLength: number, language: string?): string
	const languagePrefix = if language then language else ""
	const overhead = 8 + #languagePrefix
	const safeValue = string.gsub(truncate(value, maxLength - overhead), "```", "'''")
	return "```" .. languagePrefix .. "\n" .. safeValue .. "\n```"
end

local function formatInlineValue(value: string): string
	const safeValue = string.gsub(value, "`", "'")
	return "`" .. safeValue .. "`"
end

local function formatJsonValue(value: any, indentation: number): string
	if not t.table(value) then
		if value == nil then
			return "null"
		end

		return HttpService:JSONEncode(value)
	end

	const prefix = string.rep("  ", indentation)
	const childPrefix = string.rep("  ", indentation + 1)
	const lines = {}
	for key, nestedValue in value do
		const encodedKey = HttpService:JSONEncode(tostring(key))
		const encodedValue = formatJsonValue(nestedValue, indentation + 1)
		table.insert(lines, `{childPrefix}{encodedKey}: {encodedValue}`)
	end

	if #lines == 0 then
		return "{}"
	end

	table.sort(lines)
	return "{\n" .. table.concat(lines, ",\n") .. "\n" .. prefix .. "}"
end

local function formatStackTrace(stack: string, maxLength: number): string
	const lines = {}
	for line in string.gmatch(stack, "[^\r\n]+") do
		table.insert(lines, line)
	end

	if #lines > MAX_STACK_FRAMES then
		const remainingFrameCount = #lines - MAX_STACK_FRAMES
		while #lines > MAX_STACK_FRAMES do
			table.remove(lines)
		end
		table.insert(lines, `...{remainingFrameCount} more frames`)
	end

	return formatCodeBlock(table.concat(lines, "\n"), maxLength)
end

local function formatTitle(message: string): string
	const oneLineMessage = string.gsub(message, "[\r\n]+", " ")
	return truncate(oneLineMessage, 256)
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
		reportId = HttpService:GenerateGUID(false),
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
		return formatJsonValue(report.context, 0)
	end)
	const contextText = if contextSuccess then contextJson else "<context unavailable>"
	const stackText = report.stack or "<stack unavailable>"
	const normalizedReportId = string.upper(string.gsub(report.reportId, "-", ""))
	const shortReportId = string.sub(normalizedReportId, 1, 12)
	const timestamp = DateTime.fromUnixTimestamp(report.timestamp)
	const utcComponents = timestamp:ToUniversalTime()
	const utcText = string.format(
		"%04d-%02d-%02d %02d:%02d UTC",
		utcComponents.Year,
		utcComponents.Month,
		utcComponents.Day,
		utcComponents.Hour,
		utcComponents.Minute
	)
	const fields: { WebhookTypes.EmbedField } = {
		{
			Name = "🌎 Universe",
			Value = formatInlineValue(tostring(report.universeId)),
			Inline = true,
		},
		{
			Name = "📍 Place",
			Value = formatInlineValue(tostring(report.placeId)),
			Inline = true,
		},
		{
			Name = "👥 Players",
			Value = formatInlineValue(tostring(report.playerCount)),
			Inline = true,
		},
		{
			Name = "💻 Studio",
			Value = formatInlineValue(if report.isStudio then "Yes" else "No"),
			Inline = true,
		},
		{
			Name = "🆔 Job",
			Value = formatInlineValue(if report.jobId ~= "" then report.jobId else "<not available>"),
			Inline = true,
		},
		{
			Name = "🖥️ Realm",
			Value = formatInlineValue(report.realm),
			Inline = true,
		},
		{
			Name = "📄 Context",
			Value = formatCodeBlock(contextText, MAX_EMBED_FIELD_LENGTH, "json"),
		},
		{
			Name = "📜 Stack Trace",
			Value = formatStackTrace(stackText, MAX_EMBED_FIELD_LENGTH),
		},
		{
			Name = "🕒 Time",
			Value = `{utcText}\n<t:{report.timestamp}:R>`,
		},
	}

	return {
		Author = {
			Name = if report.severity == "fatal"
				then `❌ Fatal Error • Report #{shortReportId}`
				else `🟠 Error • Report #{shortReportId}`,
		},
		Title = formatTitle(report.message),
		Timestamp = timestamp,
		Color = if report.severity == "fatal" then FATAL_COLOR else ERROR_COLOR,
		Footer = {
			Text = `Message type: {report.messageType}`,
		},
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
	if not t.string(safeContext.stack) then
		safeContext.stack = debug.traceback(nil, 2)
	end

	local escapedMessage = string.gsub(message, "{", "{{")
	escapedMessage = string.gsub(escapedMessage, "}", "}}")
	LogService:Error(`{FATAL_PREFIX}{escapedMessage}`, safeContext)
end

--[=[
	Creates a context table containing an error value and its full traceback.

	@within ErrorReportingUtils
	@param errorValue any
	@param context { [string]: any }?
	@return { [string]: any }
]=]
function ErrorReportingUtils.createFailureContext(errorValue: any, context: { [string]: any }?): ErrorContext
	assert(t.optional(t.table)(context), "Bad context")

	const result = ErrorReportingUtils.sanitizeContext(context or {})
	result.error = tostring(errorValue)
	result.stack = debug.traceback(tostring(errorValue), 2)
	return result
end

return ErrorReportingUtils
