--!strict
--[=[
	@class RagdollMotorData
]=]

const require = require("../../../Loader").load()

local AdorneeData = require("AdorneeData")

return AdorneeData.new({
	IsMotorAnimated = false,
	RagdollSpringReturnSpeed = 20,
})
