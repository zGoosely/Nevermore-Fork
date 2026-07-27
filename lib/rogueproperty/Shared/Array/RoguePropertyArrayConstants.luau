--!strict
--[=[
	@class RoguePropertyArrayConstants
]=]

local require = require("../../../Loader").load()

local Table = require("TableUtils")

return Table.readonly({
	ARRAY_ENTRY_PERFIX = "ArrayEntry_",
})
