--!strict
--[=[
	Owns authoritative ordered chat tags and exposes their replicated observations.

	@class ChatProviderService
	@server
]=]

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const ChatProviderServiceConstants = require("@game/ReplicatedStorage/Packages/ChatProviderServiceConstants")
const ChatProviderServiceInterface = require("@game/ReplicatedStorage/Packages/ChatProviderServiceInterface")
const ChatProviderServiceTypes = require("@game/ReplicatedStorage/Packages/ChatProviderServiceTypes")
const ChatProviderServiceUtils = require("@game/ReplicatedStorage/Packages/ChatProviderServiceUtils")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const Rx = require("@game/ReplicatedStorage/Packages/Rx")
const RxPlayerUtils = require("@game/ReplicatedStorage/Packages/RxPlayerUtils")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const TieRealmService = require("@game/ReplicatedStorage/Packages/TieRealmService")
const ValueObject = require("@game/ReplicatedStorage/Packages/ValueObject")
const t = require("@game/ReplicatedStorage/Packages/t")

export type ChatTag = ChatProviderServiceTypes.ChatTag
export type ChatTagInput = ChatProviderServiceTypes.ChatTagInput
type TagState = ValueObject.ValueObject<{ ChatTag }?>

const EMPTY_TAGS: { ChatTag } = table.freeze({}) :: any

const ChatProviderService = {}
ChatProviderService.ServiceName = "ChatProviderService"
ChatProviderService.__index = ChatProviderService

export type ChatProviderService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_tieRealmService: TieRealmService.TieRealmService,
		_states: { [string]: TagState },
	},
	{} :: typeof({ __index = ChatProviderService })
))

function ChatProviderService.Init(self: ChatProviderService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._tieRealmService = serviceBag:GetService(TieRealmService)
	self._states = {}

	self._maid:GiveTask(RxPlayerUtils.observePlayersBrio():Subscribe(function(playerBrio)
		local player = playerBrio:GetValue()
		local state = self:_getState(player.Name)
		if state:GetValue() == nil then
			state:SetValue(EMPTY_TAGS)
			if player:GetAttribute(ChatProviderServiceConstants.ATTRIBUTE_NAME) == nil then
				self:_setTagsAttribute(player, EMPTY_TAGS)
			end
		end
		playerBrio:ToMaid():GiveTask(function()
			state:SetValue(nil)
		end)
	end))

	self._maid:Add(
		ChatProviderServiceInterface.Server:Implement(ReplicatedStorage, self, self._tieRealmService:GetTieRealm())
	)
end

function ChatProviderService._getState(self: ChatProviderService, userName: string): TagState
	local state = self._states[userName]
	if state then
		return state
	end

	state = self._maid:Add(ValueObject.new(nil)) :: TagState
	self._states[userName] = state
	return state
end

function ChatProviderService._setTagsAttribute(_self: ChatProviderService, player: Player, tags: { ChatTag }): ()
	player:SetAttribute(ChatProviderServiceConstants.ATTRIBUTE_NAME, ChatProviderServiceUtils.encodeChatTags(tags))
end

--[=[
	Adds or replaces one tag. The returned cleanup function removes that tag.

	@within ChatProviderService
	@param player Player
	@param input ChatTagInput
	@return () -> ()
]=]
function ChatProviderService.AddTag(self: ChatProviderService, player: Player, input: ChatTagInput): () -> ()
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(ChatProviderServiceUtils.isChatTagInput(input), "Bad input")

	local state = self:_getState(player.Name)
	local tags = state:GetValue() or EMPTY_TAGS
	local replacement = ChatProviderServiceUtils.createChatTag(input)
	local nextTags = {}
	local found = false

	for _, tag in tags do
		if tag.Id == replacement.Id then
			table.insert(nextTags, replacement)
			found = true
		else
			table.insert(nextTags, tag)
		end
	end

	if not found then
		assert(#nextTags < ChatProviderServiceConstants.MAXIMUM_TAGS_PER_USER, "Maximum chat tags exceeded")
		table.insert(nextTags, replacement)
	end

	local sortedTags = ChatProviderServiceUtils.sortChatTags(nextTags)
	state:SetValue(sortedTags)
	self:_setTagsAttribute(player, sortedTags)
	return function()
		self:RemoveTag(player, replacement.Id)
	end
end

--[=[
	Removes a tag by id.

	@within ChatProviderService
	@param player Player
	@param tagId string
	@return boolean
]=]
function ChatProviderService.RemoveTag(self: ChatProviderService, player: Player, tagId: string): boolean
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(t.string(tagId) and tagId ~= "", "Bad tagId")

	local state = self:_getState(player.Name)
	local tags = state:GetValue() or EMPTY_TAGS
	local nextTags = {}
	local removed = false
	for _, tag in tags do
		if tag.Id == tagId then
			removed = true
		else
			table.insert(nextTags, tag)
		end
	end

	if removed then
		local sortedTags = ChatProviderServiceUtils.sortChatTags(nextTags)
		state:SetValue(sortedTags)
		self:_setTagsAttribute(player, sortedTags)
	end
	return removed
end

--[=[
	Enables or disables one tag without removing it.

	@within ChatProviderService
	@param player Player
	@param tagId string
	@param enabled boolean
	@return boolean
]=]
function ChatProviderService.SetTagEnabled(
	self: ChatProviderService,
	player: Player,
	tagId: string,
	enabled: boolean
): boolean
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(t.string(tagId) and tagId ~= "", "Bad tagId")
	assert(t.boolean(enabled), "Bad enabled")

	local state = self:_getState(player.Name)
	local tags = state:GetValue() or EMPTY_TAGS
	local nextTags = {}
	local changed = false
	for _, tag in tags do
		if tag.Id == tagId then
			table.insert(
				nextTags,
				table.freeze({
					Id = tag.Id,
					Text = tag.Text,
					Order = tag.Order,
					Color = tag.Color,
					Enabled = enabled,
				})
			)
			changed = true
		else
			table.insert(nextTags, tag)
		end
	end

	if changed then
		local sortedTags = ChatProviderServiceUtils.sortChatTags(nextTags)
		state:SetValue(sortedTags)
		self:_setTagsAttribute(player, sortedTags)
	end
	return changed
end

--[=[
	Returns all tags, including disabled tags, in render order.

	@within ChatProviderService
	@param player Player
	@return { ChatTag }
]=]
function ChatProviderService.GetTags(self: ChatProviderService, player: Player): { ChatTag }
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:_getState(player.Name):GetValue() or EMPTY_TAGS
end

--[=[
	Removes every tag from a player.

	@within ChatProviderService
	@param player Player
]=]
function ChatProviderService.ClearTags(self: ChatProviderService, player: Player): ()
	assert(t.instanceIsA("Player")(player), "Bad player")
	self:_getState(player.Name):SetValue(EMPTY_TAGS)
	self:_setTagsAttribute(player, EMPTY_TAGS)
end

--[=[
	Observes all tags for a username. A missing player emits an empty list.

	@within ChatProviderService
	@param userName string
	@return Observable<{ ChatTag }>
]=]
function ChatProviderService.ObserveUserTagsByName(
	self: ChatProviderService,
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
	Observes a username while its player is present as a Brio.

	@within ChatProviderService
	@param userName string
	@return Observable<Brio<{ ChatTag }>>
]=]
function ChatProviderService.ObserveUserTagsByNameBrio(self: ChatProviderService, userName: string)
	assert(t.string(userName), "Bad userName")
	return self:_getState(userName):ObserveBrio(function(tags: { ChatTag }?): boolean
		return tags ~= nil
	end)
end

function ChatProviderService.Destroy(self: ChatProviderService): ()
	self._maid:DoCleaning()
	self._states = {}
end

return ChatProviderService
