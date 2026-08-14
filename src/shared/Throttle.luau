--!strict

const Implementation = require(script.Parent._Index["quenty/throttle@0.0.1"]["Throttle"])

export type ThrottleConfig = Implementation.ThrottleConfig
export type Func<T...> = Implementation.Func<T...>
export type Throttle<T...> = Implementation.Throttle<T...>

return Implementation
