--!strict

const Implementation = require(script.Parent._Index["quenty/profilestore@0.0.1"]["ProfileStore"])

export type JSONAcceptable = Implementation.JSONAcceptable
export type Profile<T> = Implementation.Profile<T>
export type VersionQuery<T> = Implementation.VersionQuery<T>
export type ProfileStore<T> = Implementation.ProfileStore<T>
export type ProfileStoreModule = Implementation.ProfileStoreModule

return Implementation
