--!strict
--[=[
    @class SoundGroupVolumeInterface
]=]
local TieDefinition = require("@game/ReplicatedStorage/Packages/TieDefinition")

return TieDefinition.new("SoundGroupVolume", {
	CreateMultiplier = TieDefinition.Types.METHOD,
})
