--!strict
--[=[
	Formats replicated chat tags through Roblox TextChatService.

	@class ChatProviderServiceClient
	@client
]=]

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const TextChatService = game:GetService("TextChatService")

const ChatProviderServiceConstants = require("./Shared/ChatProviderServiceConstants")
const ChatProviderServiceInterfaceDefinition = require("./Shared/ChatProviderServiceInterface")
const ChatProviderServiceTypes = require("./Shared/ChatProviderServiceTypes")
const ChatProviderServiceUtils = require("./Shared/ChatProviderServiceUtils")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const RxAttributeUtils = require("@game/ReplicatedStorage/Packages/RxAttributeUtils")
const Rx = require("@game/ReplicatedStorage/Packages/Rx")
const RxPlayerUtils = require("@game/ReplicatedStorage/Packages/RxPlayerUtils")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")
const TieRealmService = require("@game/ReplicatedStorage/Packages/TieRealmService")
const ValueObject = require("@game/ReplicatedStorage/Packages/ValueObject")

type ChatTag = ChatProviderServiceTypes.ChatTag
type TagState = ValueObject.ValueObject<{ ChatTag }?>

const EMPTY_TAGS: { ChatTag } = table.freeze({}) :: any

const ChatProviderServiceClient = {}
ChatProviderServiceClient.ServiceName = "ChatProviderServiceClient"

export type ChatProviderServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_tieRealmService: TieRealmService.TieRealmService,
		_states: { [string]: TagState },
	},
	{} :: typeof({ __index = ChatProviderServiceClient })
))

local function getPrefixWithoutColon(prefixText: string): string
	if prefixText:sub(-1) == ":" then
		return prefixText:sub(1, -2)
	end
	return prefixText
end

function ChatProviderServiceClient.Init(self: ChatProviderServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._tieRealmService = serviceBag:GetService(TieRealmService)
	self._states = {}
	self._maid:Add(
		ChatProviderServiceInterfaceDefinition.Client:Implement(
			ReplicatedStorage,
			self,
			self._tieRealmService:GetTieRealm()
		)
	)
end

function ChatProviderServiceClient.Start(self: ChatProviderServiceClient): ()
	self._maid:GiveTask(RxPlayerUtils.observePlayersBrio():Subscribe(function(playerBrio)
		local player = playerBrio:GetValue()
		playerBrio:ToMaid():GiveTask(self:_observePlayer(player))
	end))

	TextChatService.OnIncomingMessage = function(textChatMessage: TextChatMessage): TextChatMessageProperties?
		local textSource = textChatMessage.TextSource
		if not textSource then
			return nil
		end

		local player = Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			return nil
		end

		local state = self._states[player.Name]
		local tags = state and state:GetValue()
		if not tags then
			return nil
		end

		local renderedTags = ChatProviderServiceUtils.renderChatTags(tags)
		if not renderedTags then
			return nil
		end

		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = string.format(
			"%s%s%s:",
			renderedTags,
			ChatProviderServiceConstants.NAME_SEPARATOR,
			getPrefixWithoutColon(textChatMessage.PrefixText)
		)
		return properties
	end
end

--[=[
	Observes all tags for a username through replicated server-authoritative state.

	@within ChatProviderServiceClient
	@param userName string
	@return Observable<{ ChatTag }>
]=]
function ChatProviderServiceClient.ObserveUserTagsByName(
	self: ChatProviderServiceClient,
	userName: string
): Observable.Observable<{ ChatTag }>
	assert(t.string(userName), "Bad userName")
	return self:_getState(userName):Observe():Pipe({
		Rx.map(function(tags: { ChatTag }?): { ChatTag }
			return tags or EMPTY_TAGS
		end),
	})
end

--[=[
	Observes a username while its player is present through replicated server-authoritative state.

	@within ChatProviderServiceClient
	@param userName string
	@return Observable<Brio<{ ChatTag }>>
]=]
function ChatProviderServiceClient.ObserveUserTagsByNameBrio(self: ChatProviderServiceClient, userName: string)
	assert(t.string(userName), "Bad userName")
	return self:_getState(userName):ObserveBrio(function(tags: { ChatTag }?): boolean
		return tags ~= nil
	end)
end

function ChatProviderServiceClient._observePlayer(self: ChatProviderServiceClient, player: Player): Maid.Maid
	local playerName = player.Name
	local maid = Maid.new()
	local state = self:_getState(playerName)
	state:SetValue(EMPTY_TAGS)
	maid:GiveTask(
		RxAttributeUtils.observeAttribute(player, ChatProviderServiceConstants.ATTRIBUTE_NAME, nil)
			:Subscribe(function(value)
				state:SetValue(ChatProviderServiceUtils.decodeChatTags(value))
			end)
	)
	maid:GiveTask(function()
		state:SetValue(nil)
	end)
	return maid
end

function ChatProviderServiceClient._getState(self: ChatProviderServiceClient, userName: string): TagState
	local state = self._states[userName]
	if state then
		return state
	end

	state = self._maid:Add(ValueObject.new(nil)) :: TagState
	self._states[userName] = state
	return state
end

function ChatProviderServiceClient.Destroy(self: ChatProviderServiceClient): ()
	TextChatService.OnIncomingMessage = nil
	self._maid:DoCleaning()
	self._states = {}
end

return ChatProviderServiceClient
