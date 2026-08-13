--!strict

const Implementation = require(script.Parent._Index["quenty/rx@0.0.1"]["Subscription"])

export type SubscriptionState = Implementation.SubscriptionState
export type FireCallback<T...> = Implementation.FireCallback<T...>
export type CompleteCallback = Implementation.CompleteCallback
export type FailCallback = Implementation.FailCallback
export type Subscription<T...> = Implementation.Subscription<T...>
export type SubscriptionStateTypes = Implementation.SubscriptionStateTypes

return Implementation
