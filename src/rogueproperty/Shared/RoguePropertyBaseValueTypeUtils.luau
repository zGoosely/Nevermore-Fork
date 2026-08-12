--!strict
--[=[
	@class RoguePropertyBaseValueTypeUtils
]=]

local require = require("../../Loader").load()

local RoguePropertyBaseValueTypes = require("RoguePropertyBaseValueTypes")

local RoguePropertyBaseValueTypeUtils = {}

function RoguePropertyBaseValueTypeUtils.isRoguePropertyBaseValueType(value: any): boolean
	return value == RoguePropertyBaseValueTypes.INSTANCE or value == RoguePropertyBaseValueTypes.ANY
end

return RoguePropertyBaseValueTypeUtils
