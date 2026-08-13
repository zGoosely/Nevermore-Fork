--!strict
--[=[
	Resolves the game server's approximate region and replicates it as an attribute
	on ReplicatedStorage.

	@class ServerRegionService
	@server
]=]

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const ServerRegionGeolocationUtils = require("./Server/ServerRegionGeolocationUtils")
const ServerRegionServiceConstants = require("./Shared/ServerRegionServiceConstants")
const ServerRegionServiceUtils = require("./Shared/ServerRegionServiceUtils")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

const ServerRegionService = {}
ServerRegionService.ServiceName = "ServerRegionService"
ServerRegionService.ServerOnly = true

export type ServerRegionService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
	},
	{} :: typeof({ __index = ServerRegionService })
))

function ServerRegionService.Init(self: ServerRegionService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
end

function ServerRegionService.Start(self: ServerRegionService): ()
	self._maid:Add(ServerRegionGeolocationUtils.promiseRegion()
		:Then(function(region: string)
			ReplicatedStorage:SetAttribute(ServerRegionServiceConstants.REGION_ATTRIBUTE, region)
		end)
		:Catch(function(errorMessage)
			warn(`[ServerRegionService] - Failed to resolve server region ({errorMessage})`)
		end))
end

--[=[
	Returns the currently resolved server region, or nil while unavailable.

	@within ServerRegionService
	@return string?
]=]
function ServerRegionService.GetRegion(_self: ServerRegionService): string?
	return ServerRegionServiceUtils.getRegion()
end

--[=[
	Returns a promise that resolves once the server region is available.

	@within ServerRegionService
	@return Promise<string>
]=]
function ServerRegionService.PromiseRegion(_self: ServerRegionService): Promise.Promise<string>
	return ServerRegionServiceUtils.promiseRegion()
end

function ServerRegionService.Destroy(self: ServerRegionService): ()
	self._maid:DoCleaning()
end

return ServerRegionService
