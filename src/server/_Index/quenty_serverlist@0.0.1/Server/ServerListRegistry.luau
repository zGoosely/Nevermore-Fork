--!strict
--[=[
	Owns the place-scoped MemoryStoreHashMap used by the server directory.

	@class ServerListRegistry
	@server
]=]

const MemoryStoreService = game:GetService("MemoryStoreService")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const ServerListConstants = require("../Shared/ServerListConstants")
const ServerListTypes = require("../Shared/ServerListTypes")
const ServerListUtils = require("../Shared/ServerListUtils")
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

type ServerMetadata = ServerListTypes.ServerMetadata

const ServerListRegistry = {}
ServerListRegistry.ClassName = "ServerListRegistry"
ServerListRegistry.__index = ServerListRegistry

export type ServerListRegistry = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_hashMap: MemoryStoreHashMap,
		_placeId: number,
	},
	{} :: typeof({ __index = ServerListRegistry })
))

function ServerListRegistry.new(placeId: number): ServerListRegistry
	assert(t.number(placeId) and placeId >= 0 and placeId % 1 == 0, "Bad placeId")

	const self = setmetatable({}, ServerListRegistry) :: ServerListRegistry
	self._maid = Maid.new()
	self._placeId = placeId
	self._hashMap = MemoryStoreService:GetHashMap(ServerListUtils.getMapName(placeId))
	return self
end

--[=[
	Publishes one validated entry with the configured MemoryStore TTL.

	@within ServerListRegistry
	@param metadata ServerMetadata
	@return Promise
]=]
function ServerListRegistry.PublishAsync(self: ServerListRegistry, metadata: ServerMetadata): Promise.Promise<()>
	assert(ServerListUtils.isServerMetadata(metadata), "Bad metadata")
	assert(metadata.placeId == self._placeId, "Bad metadata.placeId")

	const hashMap = self._hashMap
	return Promise.spawn(function(resolve, reject)
		const succeeded, result = pcall(function()
			hashMap:SetAsync(metadata.jobId, TableUtils.copy(metadata), ServerListConstants.ENTRY_TTL_SECONDS)
		end)
		if not succeeded then
			reject(result)
			return
		end
		resolve()
	end)
end

--[=[
	Lists fresh validated entries across MemoryStore pages, capped to the requested count.

	@within ServerListRegistry
	@param maxResults number?
	@return Promise
]=]
function ServerListRegistry.ListAsync(
	self: ServerListRegistry,
	maxResults: number?
): Promise.Promise<{ ServerMetadata }>
	assert(t.optional(t.number)(maxResults), "Bad maxResults")
	const limit = maxResults or ServerListConstants.MAX_VISIBLE_SERVERS
	assert(limit > 0 and limit <= ServerListConstants.MAX_VISIBLE_SERVERS and limit % 1 == 0, "Bad maxResults")

	const hashMap = self._hashMap
	return Promise.spawn(function(resolve, reject)
		const succeeded, result = pcall(function(): { ServerMetadata }
			const servers: { ServerMetadata } = {}
			const now = os.time()
			const pages = hashMap:ListItemsAsync(math.min(limit, ServerListConstants.MEMORY_STORE_PAGE_SIZE))
			local pageCount = 0

			while pageCount < ServerListConstants.MAX_MEMORY_STORE_PAGES do
				pageCount += 1
				for _, item in pages:GetCurrentPage() do
					const value = item.value
					if
						ServerListUtils.isServerMetadata(value)
						and value.placeId == self._placeId
						and ServerListUtils.isListedServerType(value.serverType)
						and ServerListUtils.isFresh(value, now)
					then
						servers[#servers + 1] = value :: ServerMetadata
						if #servers >= limit then
							return servers
						end
					end
				end

				if pages.IsFinished or pageCount >= ServerListConstants.MAX_MEMORY_STORE_PAGES then
					return servers
				end
				pages:AdvanceToNextPageAsync()
			end
			return servers
		end)

		if not succeeded then
			reject(result)
			return
		end
		resolve(result)
	end)
end

--[=[
	Removes one job ID from the registry.

	@within ServerListRegistry
	@param jobId string
	@return Promise
]=]
function ServerListRegistry.RemoveAsync(self: ServerListRegistry, jobId: string): Promise.Promise<()>
	assert(t.string(jobId) and jobId ~= "" and #jobId <= ServerListConstants.MAX_JOB_ID_LENGTH, "Bad jobId")

	const hashMap = self._hashMap
	return Promise.spawn(function(resolve, reject)
		const succeeded, result = pcall(function()
			hashMap:RemoveAsync(jobId)
		end)
		if not succeeded then
			reject(result)
			return
		end
		resolve()
	end)
end

function ServerListRegistry.Destroy(self: ServerListRegistry): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return ServerListRegistry
