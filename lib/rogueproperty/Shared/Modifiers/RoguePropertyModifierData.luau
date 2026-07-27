--!strict
--[=[
	@class RoguePropertyModifierData
]=]

local require = require("../../../Loader").load()

local AdorneeData = require("AdorneeData")
local AdorneeDataEntry = require("AdorneeDataEntry")
local ValueBaseValue = require("ValueBaseValue")
local t: any = require("t")

return AdorneeData.new({
	Enabled = true,
	Order = 0,
	RoguePropertySourceLink = AdorneeDataEntry.new(t.optional(t.Instance), function(adornee)
		return ValueBaseValue.new(adornee, "ObjectValue", "RoguePropertySourceLink", nil)
	end),
})
