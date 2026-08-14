--!strict
--[=[
	Validates, bounds, and snapshots server-directory metadata.

	@util ServerListUtils
]=]
const ServerListConstants = require("./ServerListConstants")
const ServerListNameUtils = require("./ServerListNameUtils")
const ServerListTypes = require("./ServerListTypes")
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

type ServerMetadata = ServerListTypes.ServerMetadata
type ServerType = ServerListTypes.ServerType

const isFiniteNumber = t.intersection(t.number, function(value: number): boolean
	return value > -math.huge and value < math.huge
end)
const isInteger = t.intersection(isFiniteNumber, function(value: number): boolean
	return value % 1 == 0
end)
const isNonNegativeInteger = t.intersection(isInteger, function(value: number): boolean
	return value >= 0
end)
const isSafeNonNegativeInteger = t.intersection(isNonNegativeInteger, function(value: number): boolean
	return value <= ServerListConstants.MAX_SAFE_INTEGER
end)
const isUint16 = t.intersection(isNonNegativeInteger, function(value: number): boolean
	return value <= ServerListConstants.MAX_UINT16
end)
const isUint32 = t.intersection(isNonNegativeInteger, function(value: number): boolean
	return value <= ServerListConstants.MAX_UINT32
end)
const isJobId = t.intersection(t.string, function(value: string): boolean
	return value ~= "" and #value <= ServerListConstants.MAX_JOB_ID_LENGTH
end)
const isName = t.intersection(t.string, function(value: string): boolean
	return value ~= "" and #value <= ServerListConstants.MAX_NAME_LENGTH
end)
const isRegion = t.intersection(t.string, function(value: string): boolean
	return value ~= "" and #value <= ServerListConstants.MAX_REGION_LENGTH
end)
const isRegionSource = t.literal("configured", "audience", "external", "unknown")
const isServerType = t.literal("standard", "vip", "reserved")
const isServerMetadata = t.strictInterface({
	jobId = isJobId,
	placeId = isSafeNonNegativeInteger,
	name = isName,
	region = t.optional(isRegion),
	regionSource = isRegionSource,
	playerCount = isUint16,
	maxPlayers = isUint16,
	serverType = isServerType,
	placeVersion = isUint32,
	startedAt = isSafeNonNegativeInteger,
	updatedAt = isSafeNonNegativeInteger,
})

const ServerListUtils = {}

--[=[
	Returns whether a value is valid bounded server metadata.

	@within ServerListUtils
	@param value any
	@return boolean
]=]
function ServerListUtils.isServerMetadata(value: any): boolean
	if not isServerMetadata(value) then
		return false
	end

	const metadata = value :: ServerMetadata
	return metadata.playerCount <= metadata.maxPlayers
		and metadata.startedAt <= metadata.updatedAt
		and ServerListUtils.isRegionConfiguration(metadata.region, metadata.regionSource)
end

--[=[
	Returns whether a value is a supported region source.

	@within ServerListUtils
	@param value any
	@return boolean
]=]
function ServerListUtils.isRegionSource(value: any): boolean
	return isRegionSource(value)
end

--[=[
	Returns whether optional region metadata and its source agree. Missing regions
	must use `unknown`; present regions must identify a real source.

	@within ServerListUtils
	@param region string?
	@param source RegionSource
	@return boolean
]=]
function ServerListUtils.isRegionConfiguration(region: string?, source: ServerListTypes.RegionSource): boolean
	if not t.optional(isRegion)(region) or not isRegionSource(source) then
		return false
	end
	return if region == nil then source == "unknown" else source ~= "unknown"
end

--[=[
	Returns whether a value is a supported server type.

	@within ServerListUtils
	@param value any
	@return boolean
]=]
function ServerListUtils.isServerType(value: any): boolean
	return isServerType(value)
end

--[=[
	Returns whether the configured directory publishes this server type.

	@within ServerListUtils
	@param serverType ServerType
	@return boolean
]=]
function ServerListUtils.isListedServerType(serverType: ServerType): boolean
	assert(isServerType(serverType), "Bad serverType")
	return TableUtils.getIndex(ServerListConstants.LISTED_SERVER_TYPES, serverType) ~= nil
end

--[=[
	Returns whether metadata describes the current live or Studio fallback server.

	@within ServerListUtils
	@param server ServerMetadata
	@return boolean
]=]
function ServerListUtils.isThisMyServer(server: any): boolean
	if not ServerListUtils.isServerMetadata(server) then
		return false
	end

	const metadata = server :: ServerMetadata
	const jobId = ServerListNameUtils.resolveJobId(game.JobId, game.PlaceId, game.PlaceVersion)
	return metadata.placeId == game.PlaceId and metadata.jobId == jobId
end

--[=[
	Returns the versioned MemoryStoreHashMap name for one place.

	@within ServerListUtils
	@param placeId number
	@return string
]=]
function ServerListUtils.getMapName(placeId: number): string
	assert(isSafeNonNegativeInteger(placeId), "Bad placeId")
	return `{ServerListConstants.MAP_NAME_PREFIX}:v{ServerListConstants.MAP_VERSION}:place:{placeId}`
end

--[=[
	Returns whether metadata is still fresh at the supplied Unix timestamp.

	@within ServerListUtils
	@param metadata ServerMetadata
	@param now number
	@return boolean
]=]
function ServerListUtils.isFresh(metadata: ServerMetadata, now: number): boolean
	assert(ServerListUtils.isServerMetadata(metadata), "Bad metadata")
	assert(isSafeNonNegativeInteger(now), "Bad now")
	return metadata.updatedAt <= now + ServerListConstants.MAX_CLOCK_SKEW_SECONDS
		and metadata.updatedAt + ServerListConstants.ENTRY_TTL_SECONDS >= now
end

--[=[
	Clones and freezes one metadata record.

	@within ServerListUtils
	@param metadata ServerMetadata
	@return ServerMetadata
]=]
function ServerListUtils.cloneMetadata(metadata: ServerMetadata): ServerMetadata
	assert(ServerListUtils.isServerMetadata(metadata), "Bad metadata")
	return table.freeze(TableUtils.copy(metadata)) :: ServerMetadata
end

--[=[
	Returns a bounded immutable snapshot whose records cannot be mutated by callers.

	@within ServerListUtils
	@param servers { ServerMetadata }
	@return { ServerMetadata }
]=]
function ServerListUtils.createSnapshot(servers: { ServerMetadata }): { ServerMetadata }
	assert(t.array(ServerListUtils.isServerMetadata)(servers), "Bad servers")

	const count = math.min(#servers, ServerListConstants.MAX_VISIBLE_SERVERS)
	const snapshot = table.create(count)
	for index = 1, count do
		snapshot[index] = ServerListUtils.cloneMetadata(servers[index])
	end
	return table.freeze(snapshot) :: { ServerMetadata }
end

--[=[
	Returns a fresh immutable copy suitable for handing to an API caller.

	@within ServerListUtils
	@param snapshot { ServerMetadata }
	@return { ServerMetadata }
]=]
function ServerListUtils.copySnapshot(snapshot: { ServerMetadata }): { ServerMetadata }
	return ServerListUtils.createSnapshot(snapshot)
end

--[=[
	Removes one exact ByteNet listener during cleanup.

	@within ServerListUtils
	@param networkMember any
	@param listener callback
]=]
function ServerListUtils.removeNetworkListener(networkMember: any, listener: (...any) -> ...any): ()
	assert(t.table(networkMember), "Bad networkMember")
	assert(t.callback(listener), "Bad listener")

	const listeners = networkMember.getListeners()
	const index = TableUtils.getIndex(listeners, listener)
	if index then
		TableUtils.swapRemove(listeners, index)
	end
end

return ServerListUtils
