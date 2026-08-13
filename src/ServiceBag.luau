--!strict

const Implementation = require(script.Parent._Index["quenty/servicebag@0.0.1"]["ServiceBag"])

export type ServiceBag = Implementation.ServiceBag
export type ServiceDefinition<T> = Implementation.ServiceDefinition<T>
export type ServiceType<T> = Implementation.ServiceType<T>

return Implementation
