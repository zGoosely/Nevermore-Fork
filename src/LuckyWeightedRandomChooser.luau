--!strict

const Implementation = require(script.Parent._Index["quenty/random@0.0.1"]["LuckyWeightedRandomChooser"])

export type Weight = Implementation.Weight
export type Weights<T> = Implementation.Weights<T>
export type Config = Implementation.Config
export type LuckyWeightedRandomChooser<T> = Implementation.LuckyWeightedRandomChooser<T>

return Implementation
