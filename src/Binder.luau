--!strict

const Implementation = require(script.Parent._Index["quenty/binder@0.0.1"]["Shared"]["Binder"])

export type ConstructorCallback<T> = Implementation.ConstructorCallback<T>
export type ClassDefinition<T> = Implementation.ClassDefinition<T>
export type ProviderDefition<T> = Implementation.ProviderDefition<T>
export type BinderConstructor<T> = Implementation.BinderConstructor<T>
export type Binder<T> = Implementation.Binder<T>

return Implementation
