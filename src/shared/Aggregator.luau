--!strict

const Implementation = require(script.Parent._Index["quenty/aggregator@0.0.1"]["Aggregator"])

export type PromiseBulkQuery<T> = Implementation.PromiseBulkQuery<T>
export type Aggregator<T> = Implementation.Aggregator<T>

return Implementation
