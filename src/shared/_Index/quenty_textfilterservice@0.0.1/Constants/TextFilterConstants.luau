--!strict
--[=[
	@class TextFilterConstants
]=]
local Table = require("@game/ReplicatedStorage/Packages/TableUtils")

return Table.readonly({
	REQUEST_TYPES = {
		REQUEST_NON_CHAT_STRING_FOR_USER = "1",
		REQUEST_NON_CHAT_STRING_FOR_BROADCAST = "2",
		REQUEST_PREVIEW_NON_CHAT_STRING_FOR_BROADCAST = "3",
	},
})
