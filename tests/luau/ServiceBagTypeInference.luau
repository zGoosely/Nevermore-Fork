--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const Packages = ReplicatedStorage.Packages

const GameConfigService = require(Packages.GameConfigService)
const ServiceBag = require(Packages.ServiceBag)

const serviceBag = ServiceBag.new()
const resolved = serviceBag:GetService(GameConfigService)

return resolved:GetConfigPicker()
