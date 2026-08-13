--!strict

const ServiceBag = require("../src/ServiceBag")

type ExampleService = {
	Init: (self: ExampleService, serviceBag: ServiceBag.ServiceBag) -> (),
	GetValue: (self: ExampleService) -> number,
}

const ExampleService = {} :: ExampleService
const serviceBag = ServiceBag.new()
const resolved: ExampleService = serviceBag:GetService(ExampleService)

const value: number = resolved:GetValue()
return value
