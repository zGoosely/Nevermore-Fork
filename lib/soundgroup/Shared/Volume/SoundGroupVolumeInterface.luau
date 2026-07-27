--!strict
--[=[
    @class SoundGroupVolumeInterface
]=]

local require = require("../../../Loader").load()

local TieDefinition = require("TieDefinition")

return TieDefinition.new("SoundGroupVolume", {
	CreateMultiplier = TieDefinition.Types.METHOD,
})
