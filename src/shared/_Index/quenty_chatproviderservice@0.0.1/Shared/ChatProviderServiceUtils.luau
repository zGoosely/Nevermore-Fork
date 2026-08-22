--!strict
--[=[
	Stateless chat tag validation, ordering, and rendering helpers.

	@util ChatProviderServiceUtils
]=]

const HttpService = game:GetService("HttpService")

const ChatProviderServiceConstants = require("./ChatProviderServiceConstants")
const ChatProviderServiceTypes = require("./ChatProviderServiceTypes")
const t = require("@game/ReplicatedStorage/Packages/t")

type ChatTag = ChatProviderServiceTypes.ChatTag
type ChatTagInput = ChatProviderServiceTypes.ChatTagInput

const ChatProviderServiceUtils = {}

const isChatTagInput = t.strictInterface({
	Id = t.string,
	Text = t.string,
	Order = t.optional(t.number),
	Color = t.optional(t.Color3),
	Enabled = t.optional(t.boolean),
})

local function compareTags(left: ChatTag, right: ChatTag): boolean
	if left.Order == right.Order then
		return left.Id < right.Id
	end
	return left.Order < right.Order
end

local function escapeRichText(text: string): string
	return text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\"", "&quot;")
end

local function isSerializedColor(value: unknown): boolean
	return t.strictInterface({
		R = t.number,
		G = t.number,
		B = t.number,
	})(value)
end

local function isSerializedTag(value: unknown): boolean
	return t.strictInterface({
		Id = t.string,
		Text = t.string,
		Order = t.number,
		Color = isSerializedColor,
		Enabled = t.boolean,
	})(value)
end

--[=[
	Validates a tag input and its semantic limits.
	@within ChatProviderServiceUtils
	@param input ChatTagInput
	@return boolean
]=]
function ChatProviderServiceUtils.isChatTagInput(input: unknown): boolean
	return isChatTagInput(input)
		and (input :: ChatTagInput).Id ~= ""
		and (input :: ChatTagInput).Text ~= ""
		and #(input :: ChatTagInput).Text <= ChatProviderServiceConstants.MAXIMUM_TAG_TEXT_LENGTH
end

--[=[
	Creates an immutable tag from optional defaults.
	@within ChatProviderServiceUtils
	@param input ChatTagInput
	@return ChatTag
]=]
function ChatProviderServiceUtils.createChatTag(input: ChatTagInput): ChatTag
	assert(ChatProviderServiceUtils.isChatTagInput(input), "Bad input")
	return table.freeze({
		Id = input.Id,
		Text = input.Text,
		Order = input.Order or ChatProviderServiceConstants.DEFAULT_ORDER,
		Color = input.Color or ChatProviderServiceConstants.DEFAULT_COLOR,
		Enabled = if input.Enabled == nil then true else input.Enabled,
	})
end

--[=[
	Returns a sorted immutable copy of the provided tags.
	@within ChatProviderServiceUtils
	@param tags { ChatTag }
	@return { ChatTag }
]=]
function ChatProviderServiceUtils.sortChatTags(tags: { ChatTag }): { ChatTag }
	local result = table.clone(tags)
	table.sort(result, compareTags)
	return table.freeze(result)
end

--[=[
	Encodes tags into a replicated attribute string.
	@within ChatProviderServiceUtils
	@param tags { ChatTag }
	@return string
]=]
function ChatProviderServiceUtils.encodeChatTags(tags: { ChatTag }): string
	local encoded = {}
	for _, tag in tags do
		table.insert(encoded, {
			Id = tag.Id,
			Text = tag.Text,
			Order = tag.Order,
			Color = {
				R = tag.Color.R,
				G = tag.Color.G,
				B = tag.Color.B,
			},
			Enabled = tag.Enabled,
		})
	end
	return HttpService:JSONEncode(encoded)
end

--[=[
	Decodes replicated tag state, returning an empty list for invalid data.
	@within ChatProviderServiceUtils
	@param value unknown
	@return { ChatTag }
]=]
function ChatProviderServiceUtils.decodeChatTags(value: unknown): { ChatTag }
	if not t.string(value) then
		return table.freeze({})
	end

	local success, decoded = pcall(function()
		return HttpService:JSONDecode(value :: string)
	end)
	if not success or not t.table(decoded) then
		return table.freeze({})
	end

	local tags = {}
	for _, item in decoded do
		if isSerializedTag(item) then
			local serialized = item :: {
				Id: string,
				Text: string,
				Order: number,
				Color: { R: number, G: number, B: number },
				Enabled: boolean,
			}
			table.insert(
				tags,
				table.freeze({
					Id = serialized.Id,
					Text = serialized.Text,
					Order = serialized.Order,
					Color = Color3.new(serialized.Color.R, serialized.Color.G, serialized.Color.B),
					Enabled = serialized.Enabled,
				})
			)
		end
	end
	return ChatProviderServiceUtils.sortChatTags(tags)
end

--[=[
	Renders enabled tags as colored RichText.
	@within ChatProviderServiceUtils
	@param tags { ChatTag }
	@return string?
]=]
function ChatProviderServiceUtils.renderChatTags(tags: { ChatTag }): string?
	local rendered = {}
	for _, tag in tags do
		if tag.Enabled then
			table.insert(
				rendered,
				string.format(
					"<font color=\"#%s\">%s%s%s</font>",
					tag.Color:ToHex(),
					escapeRichText(ChatProviderServiceConstants.PREFIX_OPEN),
					escapeRichText(tag.Text),
					escapeRichText(ChatProviderServiceConstants.PREFIX_CLOSE)
				)
			)
		end
	end

	if #rendered == 0 then
		return nil
	end
	return table.concat(rendered, ChatProviderServiceConstants.TAG_SEPARATOR)
end

return ChatProviderServiceUtils
