--!strict

const Implementation = require(script.Parent._Index["quenty/promise@0.0.1"]["Promise"])

export type Resolve<T...> = Implementation.Resolve<T...>
export type Reject = Implementation.Reject
export type ResolveReject<T...> = Implementation.ResolveReject<T...>
export type Promise<T...> = Implementation.Promise<T...>

return Implementation
