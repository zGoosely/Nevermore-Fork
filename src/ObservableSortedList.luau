--!strict

const Implementation = require(script.Parent._Index["quenty/sortedlist@0.0.1"]["ObservableSortedList"])

export type CompareFunction<T> = Implementation.CompareFunction<T>
export type ObservableSortedList<T> = Implementation.ObservableSortedList<T>

return Implementation
