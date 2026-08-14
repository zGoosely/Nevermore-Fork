--!strict
--[=[
	@class RoguePropertyModifierData
]=]
local AdorneeData = require("@game/ReplicatedStorage/Packages/AdorneeData")
local AdorneeDataEntry = require("@game/ReplicatedStorage/Packages/AdorneeDataEntry")
local ValueBaseValue = require("@game/ReplicatedStorage/Packages/ValueBaseValue")
local t: any = require("@game/ReplicatedStorage/Packages/t")

return AdorneeData.new({
	Enabled = true,
	Order = 0,
	RoguePropertySourceLink = AdorneeDataEntry.new(t.optional(t.Instance), function(adornee)
		return ValueBaseValue.new(adornee, "ObjectValue", "RoguePropertySourceLink", nil)
	end),
})
