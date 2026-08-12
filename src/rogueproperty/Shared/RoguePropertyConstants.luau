--!strict
--[=[
	@class RoguePropertyConstants
]=]

local require = require("../../Loader").load()

local Table = require("TableUtils")

return Table.readonly({
	INSTANCE_ATTRIBUTE_VALUE = "_DATAMODEL_INSTANCE",
})
