--!strict

const Implementation = require(script.Parent._Index["quenty/rx@0.0.1"]["Observable"])

export type OnSubscribe<T...> = Implementation.OnSubscribe<T...>
export type Transformer<T..., U...> = Implementation.Transformer<T..., U...>
export type Observable<T...> = Implementation.Observable<T...>

return Implementation
