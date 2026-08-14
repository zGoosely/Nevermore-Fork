--!strict

const Implementation = require(script.Parent._Index["quenty/singleton@0.0.1"]["Singleton"])

export type Constructor<T> = Implementation.Constructor<T>
export type Singleton<T> = Implementation.Singleton<T>

return Implementation
