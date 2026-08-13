--!strict

const Implementation = require(script.Parent._Index["quenty/signal@0.0.1"]["Signal"])

export type Connection<U...> = Implementation.Connection<U...>
export type Signal<T...> = Implementation.Signal<T...>

return Implementation
