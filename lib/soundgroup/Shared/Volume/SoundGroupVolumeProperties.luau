--!strict
--[=[
	@class SoundGroupVolumeProperties
]=]

local require = require("../../../Loader").load()

local RoguePropertyTableDefinition = require("RoguePropertyTableDefinition")

return RoguePropertyTableDefinition.new("SoundGroupVolume", {
	Volume = 1,
})
