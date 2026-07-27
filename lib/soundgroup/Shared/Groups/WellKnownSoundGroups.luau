--!strict
--[=[
	@class WellKnownSoundGroups
]=]

local require = require("../../../Loader").load()

local Table = require("TableUtils")

export type WellKnownSoundGroups = {
	MASTER: "Master",
	SFX: "Master.SoundEffects",
	MUSIC: "Master.Music",
	VOICE: "Master.Voice",
}

return Table.readonly({
	MASTER = "Master",

	SFX = "Master.SoundEffects",
	MUSIC = "Master.Music",
	VOICE = "Master.Voice",
} :: WellKnownSoundGroups)
