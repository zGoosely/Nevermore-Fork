--!strict

const Implementation = require(script.Parent._Index["quenty/ratelimiter@0.0.1"]["RateLimiter"])

export type Clock = Implementation.Clock
export type RateLimiter = Implementation.RateLimiter

return Implementation
