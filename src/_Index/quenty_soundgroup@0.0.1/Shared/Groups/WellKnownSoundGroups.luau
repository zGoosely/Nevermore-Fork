--!strict
--[=[
	@class WellKnownSoundGroups
]=]
local Table = require("@game/ReplicatedStorage/Packages/TableUtils")

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
