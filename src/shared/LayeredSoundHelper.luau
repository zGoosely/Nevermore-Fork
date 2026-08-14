--!strict

const Implementation =
	require(script.Parent._Index["quenty/soundplayer@0.0.1"]["Client"]["Loops"]["Layered"]["LayeredSoundHelper"])

export type CreateSoundPlayer<T> = Implementation.CreateSoundPlayer<T>
export type LayeredSoundHelper<T> = Implementation.LayeredSoundHelper<T>

return Implementation
