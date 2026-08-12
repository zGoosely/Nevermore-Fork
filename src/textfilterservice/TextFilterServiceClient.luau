--!nonstrict
--[=[
	@class TextFilterServiceClient
]=]

const Players = game:GetService("Players")
const require = require("../Loader").load()

const Promise = require("Promise")
const ServiceBag = require("ServiceBag")
const TextFilterConstants = require("TextFilterConstants")
const t = require("t")
const TextFilterNetwork = require("TextFilterNetwork")

const Player = Players.LocalPlayer
const UserId = Player.UserId

const TextFilterServiceClient = {}
TextFilterServiceClient.ServiceName = "TextFilterServiceClient"

export type TextFilterServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
	},
	{} :: typeof({ __index = TextFilterServiceClient })
))

function TextFilterServiceClient.Init(self: TextFilterServiceClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
end

--[=[
	Promises a filtered chat message from the local player.

	@param text string
	@return Promise<any>
]=]
function TextFilterServiceClient.PromiseFilteredTextFromLocalPlayer(
	self: TextFilterServiceClient,
	text: string
): Promise.Promise<any>
	assert(t.string(text))
	return self:PromiseNonChatStringForBroadcast(text, UserId)
end

--[=[
	Promises a filtered non-chat string for a user.

	@param text string
	@param fromUserId number
	@return Promise<any>
]=]
function TextFilterServiceClient.PromiseNonChatStringForUser(self: TextFilterServiceClient, text, fromUserId): any
	assert(t.string(text))
	assert(t.number(fromUserId))

	return self:_promiseFilterInvoke(
		TextFilterConstants.REQUEST_TYPES.REQUEST_NON_CHAT_STRING_FOR_USER,
		text,
		fromUserId
	)
end

--[=[
	Promises a filtered non-chat string for broadcast.

	@param text string
	@param fromUserId number
	@return Promise<any>
]=]
function TextFilterServiceClient.PromiseNonChatStringForBroadcast(self: TextFilterServiceClient, text, fromUserId): any
	assert(t.string(text))
	assert(t.number(fromUserId))

	return self:_promiseFilterInvoke(
		TextFilterConstants.REQUEST_TYPES.REQUEST_NON_CHAT_STRING_FOR_BROADCAST,
		text,
		fromUserId
	)
end

--[=[
	Promises a preview of a filtered non-chat string for broadcast.

	@param text string
	@return Promise<any>
]=]
function TextFilterServiceClient.PromisePreviewNonChatStringForBroadcast(
	self: TextFilterServiceClient,
	text
): Promise.Promise<string>
	assert(t.string(text))

	return self:_promiseFilterInvoke(
		TextFilterConstants.REQUEST_TYPES.REQUEST_PREVIEW_NON_CHAT_STRING_FOR_BROADCAST,
		text
	)
end

function TextFilterServiceClient._promiseFilterInvoke(
	self: TextFilterServiceClient,
	request: string,
	text: string,
	...
): Promise.Promise<any>
	assert(t.string(text))
	assert(t.string(request))

	const args = table.pack(...)
	const promise = Promise.new()

	-- Studio doesn't allow test-session filtering
	-- So we return a fake text that replicates if it were to be filtered
	-- if RunService:IsStudio() then
	-- 	return TextFilterServiceClient._fakeTestFilter(text)
	-- end

	const success, resultOrErr = pcall(function(...)
		return TextFilterNetwork.queries.request.invoke({
			type = request,
			text = text,
			id = table.unpack(args, 1, args.n),
		})
	end)

	if success then
		promise:Resolve(resultOrErr)
	else
		warn(`[TextFilterServiceClient] - Failed while requesting ({resultOrErr})`)
		promise:Reject(resultOrErr)
	end

	return promise
end

return TextFilterServiceClient
