--!strict

const Implementation = require(script.Parent._Index["quenty/enums@0.0.1"]["Enums"])

export type EnumValue = Implementation.EnumValue
export type SimpleEnum<EnumMembers> = Implementation.SimpleEnum<EnumMembers>
export type PrivateSimpleEnum<EnumMembers> = Implementation.PrivateSimpleEnum<EnumMembers>

return Implementation
