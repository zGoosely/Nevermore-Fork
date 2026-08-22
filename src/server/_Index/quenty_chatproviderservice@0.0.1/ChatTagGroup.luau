--!strict
--[=[
	Reusable membership-backed chat tag group.

	@class ChatTagGroup
	@server
]=]

local BaseObject = require("@game/ReplicatedStorage/Packages/BaseObject")
local Brio = require("@game/ReplicatedStorage/Packages/Brio")
local ChatProviderServiceTypes = require("@game/ReplicatedStorage/Packages/ChatProviderServiceTypes")
local ChatProviderServiceUtils = require("@game/ReplicatedStorage/Packages/ChatProviderServiceUtils")
local Observable = require("@game/ReplicatedStorage/Packages/Observable")
local ObservableSet = require("@game/ReplicatedStorage/Packages/ObservableSet")
local t = require("@game/ReplicatedStorage/Packages/t")

type ChatTag = ChatProviderServiceTypes.ChatTag
type ChatTagInput = ChatProviderServiceTypes.ChatTagInput
type AddTag = (Player, ChatTagInput) -> () -> ()
type RemoveTag = (Player, string) -> boolean

const ChatTagGroup = setmetatable({}, BaseObject)
ChatTagGroup.ClassName = "ChatTagGroup"
ChatTagGroup.__index = ChatTagGroup

export type ChatTagGroup =
	typeof(setmetatable(
		{} :: {
			_tagInfo: ChatTag,
			_addTag: AddTag,
			_removeTag: RemoveTag,
			_members: ObservableSet.ObservableSet<Player>,
			_revokeByPlayer: { [Player]: () -> () },
		},
		{} :: typeof({ __index = ChatTagGroup })
	))
	& BaseObject.BaseObject

--[=[
	Constructs a reusable membership-backed tag group.
	@param tagInfo ChatTagInput
	@param addTag Server tag insertion callback
	@param removeTag Server tag removal callback
	@return ChatTagGroup
]=]
function ChatTagGroup.new(tagInfo: ChatTagInput, addTag: AddTag, removeTag: RemoveTag): ChatTagGroup
	assert(ChatProviderServiceUtils.isChatTagInput(tagInfo), "Bad tagInfo")
	assert(t.callback(addTag), "Bad addTag")
	assert(t.callback(removeTag), "Bad removeTag")

	local self = setmetatable(BaseObject.new() :: any, ChatTagGroup) :: ChatTagGroup
	self._tagInfo = ChatProviderServiceUtils.createChatTag(tagInfo)
	self._addTag = addTag
	self._removeTag = removeTag
	self._members = self._maid:Add(ObservableSet.new())
	self._revokeByPlayer = {}
	return self
end

--[=[
	Adds a player to the group and applies the group's tag.
	@within ChatTagGroup
	@param player Player
	@return () -> ()
]=]
function ChatTagGroup.AddToGroup(self: ChatTagGroup, player: Player): () -> ()
	assert(t.instanceIsA("Player")(player), "Bad player")
	if self._revokeByPlayer[player] then
		return function() end
	end

	const revoke = self._addTag(player, self._tagInfo)
	self._revokeByPlayer[player] = revoke
	self._members:Add(player)
	return function()
		self:RemoveFromGroup(player)
	end
end

--[=[
	Removes a player from the group and revokes the group's tag.
	@within ChatTagGroup
	@param player Player
	@return boolean
]=]
function ChatTagGroup.RemoveFromGroup(self: ChatTagGroup, player: Player): boolean
	assert(t.instanceIsA("Player")(player), "Bad player")
	local revoke = self._revokeByPlayer[player]
	if not revoke then
		return false
	end

	revoke()
	self._revokeByPlayer[player] = nil
	self._members:Remove(player)
	return true
end

--[=[
	Observes current group members as player Brios.
	@within ChatTagGroup
	@return Observable<Brio<Player>>
]=]
function ChatTagGroup.Observe(self: ChatTagGroup): Observable.Observable<Brio.Brio<Player>>
	return self._members:ObserveItemsBrio()
end

--[=[
	Returns the immutable tag definition used by this group.
	@within ChatTagGroup
	@return ChatTag
]=]
function ChatTagGroup.GetTagInfo(self: ChatTagGroup): ChatTag
	return self._tagInfo
end

function ChatTagGroup.Destroy(self: ChatTagGroup): ()
	for player, revoke in self._revokeByPlayer do
		revoke()
		self._revokeByPlayer[player] = nil
	end
	BaseObject.Destroy(self)
end

return ChatTagGroup
