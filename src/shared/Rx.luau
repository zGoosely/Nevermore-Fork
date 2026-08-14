--!strict

const Implementation = require(script.Parent._Index["quenty/rx@0.0.1"]["Rx"])

export type Map<Key, Value> = Implementation.Map<Key, Value>
export type Set<T> = Implementation.Set<T>
export type Predicate<T...> = Implementation.Predicate<T...>

return Implementation
