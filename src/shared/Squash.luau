--!strict

const Implementation = require(script.Parent._Index["quenty/squash@0.0.1"]["Squash"])

export type Cursor = Implementation.Cursor
export type SerDes<T...> = Implementation.SerDes<T...>
export type Length = Implementation.Length
export type SquashRaycastResult = Implementation.SquashRaycastResult

return Implementation
