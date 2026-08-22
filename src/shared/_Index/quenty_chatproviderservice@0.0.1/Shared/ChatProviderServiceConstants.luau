--!strict
--[=[
	Configuration for the chat provider tag renderer.

	@class ChatProviderServiceConstants
]=]

const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly({
	DEFAULT_COLOR = Color3.fromRGB(255, 255, 255),
	ATTRIBUTE_NAME = "ChatProviderServiceTags",
	DEFAULT_ORDER = 100,
	MAXIMUM_TAGS_PER_USER = 16,
	MAXIMUM_TAG_TEXT_LENGTH = 32,
	PREFIX_OPEN = "[",
	PREFIX_CLOSE = "]",
	TAG_SEPARATOR = " ",
	NAME_SEPARATOR = " ",
})
