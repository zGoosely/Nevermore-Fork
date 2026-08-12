--!strict
--[=[
	@class RoguePropertyBaseValueTypes
]=]

local require = require("../../Loader").load()

local SimpleEnum = require("Enums")

return SimpleEnum.new({
	INSTANCE = "instance" :: "instance",
	ANY = "any" :: "any",
})
