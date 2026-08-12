--!strict
--[=[
	@class ClipCharacterConstants
]=]

local require = require("../../Loader").load()

local TableUtils = require("TableUtils")

return TableUtils.readonly({
	COLLISION_GROUP_NAME = "ClipCharacters",
})
