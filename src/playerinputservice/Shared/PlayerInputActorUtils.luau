--!strict
--[=[
	Validates actors accepted by the authoritative PlayerInputService.

	@util PlayerInputActorUtils
]=]

const require = require("../../Loader").load()

const t = require("t")

const PlayerInputActorUtils = {}

--[=[
	Returns whether a value is a Player or a Humanoid character Model.

	@within PlayerInputActorUtils
	@param value any
	@return boolean
]=]
function PlayerInputActorUtils.isInputActor(value: any): boolean
	if t.instanceIsA("Player")(value) then
		return true
	end

	return t.instanceIsA("Model")(value) and value:FindFirstChildWhichIsA("Humanoid") ~= nil
end

return PlayerInputActorUtils
