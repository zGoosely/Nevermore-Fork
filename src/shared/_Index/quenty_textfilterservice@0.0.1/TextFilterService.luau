--!strict
--[=[
	@class TextFilterService
]=]

const TextService = game:GetService("TextService")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const TextFilterConstants = require("./Constants/TextFilterConstants")
const t = require("@game/ReplicatedStorage/Packages/t")
const TextFilterNetwork = require("./Constants/TextFilterNetwork")

const TextFilterService = {}
TextFilterService.ServiceName = "TextFilterService"

export type TextFilterService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
	},
	{} :: typeof({ __index = TextFilterService })
))

function TextFilterService.Init(self: TextFilterService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
end

function TextFilterService.Start(self: TextFilterService)
	TextFilterNetwork.queries.request.listen(
		function(request: { id: number, text: string, type: string }, player: Player?): { string }
			return self:_handleServerInvoke(player, request.type, request.text, request.id) :: any
		end
	)
end

--[=[
	Promises a filtered non-chat string for a user.

	@param player Player
	@param text string
	@param fromUserId number
	@return Promise<any>
]=]
function TextFilterService.PromiseNonChatStringForUser(
	self: TextFilterService,
	player,
	text,
	fromUserId: number
): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player))
	assert(t.string(text))
	assert(t.number(fromUserId))

	local promise = self:_promiseNonChatStringForUserAsync(
		text,
		fromUserId,
		player.UserId,
		Enum.TextFilterContext.PublicChat
	):Catch(function(_)
		return self:_promiseLegacyChatFilter(player, text)
	end)

	return promise
end

--[=[
	Promises a filtered non-chat string for broadcast.

	@param player Player
	@param text string
	@param fromUserId number
	@return Promise<any>
]=]
function TextFilterService.PromiseNonChatStringForBroadcast(
	self: TextFilterService,
	player,
	text,
	fromUserId: number
): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player))
	assert(t.string(text))
	assert(t.number(fromUserId))

	local promise = self:_promiseNonChatStringForBroadcast(text, fromUserId, Enum.TextFilterContext.PublicChat)
		:Catch(function()
			return self:_promiseLegacyChatFilter(player, text)
		end)

	return promise
end

--[=[
	Promises a preview of a filtered non-chat string for broadcast.

	@param player Player
	@param text string
	@return Promise<any>
]=]
function TextFilterService.PromisePreviewNonChatStringForBroadcast(
	self: TextFilterService,
	player,
	text
): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player))
	assert(t.string(text))

	return self:_promiseLegacyChatFilter(player, text)
end

function TextFilterService._turnRequestToPromise(self: TextFilterService, player, request, ...)
	assert(t.instanceIsA("Player")(player))
	assert(t.string(request))

	if request == TextFilterConstants.REQUEST_TYPES.REQUEST_NON_CHAT_STRING_FOR_USER then
		return self:PromiseNonChatStringForUser(player, ...)
	elseif request == TextFilterConstants.REQUEST_TYPES.REQUEST_NON_CHAT_STRING_FOR_BROADCAST then
		return self:PromiseNonChatStringForBroadcast(player, ...)
	elseif request == TextFilterConstants.REQUEST_TYPES.REQUEST_PREVIEW_NON_CHAT_STRING_FOR_BROADCAST then
		return self:PromisePreviewNonChatStringForBroadcast(player, ...)
	end

	return nil :: any
end

function TextFilterService._handleServerInvoke(self: TextFilterService, player, ...): Promise.Promise<any> | nil
	local promise = self:_turnRequestToPromise(player, ...)
	local ok, result = promise:Yield()

	if not ok then
		return nil
	end

	return result
end

function TextFilterService._promiseNonChatStringForUserAsync(
	_self: TextFilterService,
	text,
	fromUserId,
	toUserId,
	textFilterContext
)
	return Promise.new(function(resolve, reject)
		local success, result = pcall(function()
			return TextService:FilterStringAsync(text, fromUserId, textFilterContext)
				:GetNonChatStringForUserAsync(toUserId)
		end)
		if success then
			resolve(result)
		else
			reject()
		end
	end)
end

function TextFilterService._promiseNonChatStringForBroadcast(
	_self: TextFilterService,
	text,
	fromUserId,
	textFilterContext
)
	return Promise.new(function(resolve, reject)
		local success, result = pcall(function()
			return TextService:FilterStringAsync(text, fromUserId, textFilterContext)
				:GetNonChatStringForBroadcastAsync()
		end)
		if success then
			resolve(result)
		else
			reject()
		end
	end)
end

function TextFilterService._promiseLegacyChatFilter(_self: TextFilterService, player, text)
	return Promise.new(function(resolve, reject)
		local success, result = pcall(function()
			local filterResult = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
			return filterResult:GetNonChatStringForBroadcastAsync()
		end)
		if success then
			resolve(result)
		else
			reject()
		end
	end)
end

return TextFilterService
