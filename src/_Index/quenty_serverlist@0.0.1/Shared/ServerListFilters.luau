--!strict
--[=[
	Builds and applies immutable local server-list filter descriptors.

	@util ServerListFilters
]=]
const ServerListConstants = require("./ServerListConstants")
const ServerListTypes = require("./ServerListTypes")
const ServerListUtils = require("./ServerListUtils")
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

type FilterDescriptor = ServerListTypes.FilterDescriptor
type FilterName = ServerListTypes.FilterName
type ServerMetadata = ServerListTypes.ServerMetadata

type Ordering = "Recent" | "MostPlayers" | "LeastPlayers"

const isFilterName = t.literal("Recent", "Available", "NotEmpty", "Region", "MostPlayers", "LeastPlayers")
const isFilterShape = t.strictInterface({
	name = isFilterName,
	option = t.optional(t.string),
})

const ServerListFilters = {}

local function compareRecent(left: ServerMetadata, right: ServerMetadata): boolean
	if left.startedAt ~= right.startedAt then
		return left.startedAt > right.startedAt
	end
	if left.updatedAt ~= right.updatedAt then
		return left.updatedAt > right.updatedAt
	end
	return left.jobId < right.jobId
end

local function isFilterSemanticallyValid(filter: FilterDescriptor): boolean
	if filter.name == "Region" then
		return filter.option ~= nil and filter.option ~= "" and #filter.option <= ServerListConstants.MAX_REGION_LENGTH
	end
	return filter.option == nil
end

local function isOrdering(name: FilterName): boolean
	return name == "MostPlayers" or name == "LeastPlayers"
end

--[=[
	Returns an immutable validated filter descriptor. Only `Region` accepts an option,
	and it requires a non-empty bounded region string.

	@within ServerListFilters
	@param name FilterName
	@param option string?
	@return FilterDescriptor
]=]
function ServerListFilters.new(name: FilterName, option: string?): FilterDescriptor
	assert(isFilterName(name), "Bad name")
	assert(t.optional(t.string)(option), "Bad option")

	const filter = {
		name = name,
		option = option,
	} :: FilterDescriptor
	assert(isFilterSemanticallyValid(filter), "Bad option")
	return table.freeze(filter)
end

--[=[
	Returns whether a value is a valid server-list filter descriptor.

	@within ServerListFilters
	@param value any
	@return boolean
]=]
function ServerListFilters.isFilterDescriptor(value: any): boolean
	return isFilterShape(value) and isFilterSemanticallyValid(value :: FilterDescriptor)
end

--[=[
	Returns whether a value is a bounded, unambiguous array of filter descriptors.

	@within ServerListFilters
	@param value any
	@return boolean
]=]
function ServerListFilters.isFilterArray(value: any): boolean
	if not t.array(ServerListFilters.isFilterDescriptor)(value) or #value > ServerListConstants.MAX_FILTERS then
		return false
	end

	const seenNames: { [FilterName]: true } = {}
	local hasOrdering = false
	for _, filter in value :: { FilterDescriptor } do
		if seenNames[filter.name] or (isOrdering(filter.name) and hasOrdering) then
			return false
		end
		seenNames[filter.name] = true
		hasOrdering = hasOrdering or isOrdering(filter.name)
	end
	return true
end

--[=[
	Returns an immutable copy of a validated filter array.

	@within ServerListFilters
	@param filters { FilterDescriptor }
	@return { FilterDescriptor }
]=]
function ServerListFilters.createSnapshot(filters: { FilterDescriptor }): { FilterDescriptor }
	assert(ServerListFilters.isFilterArray(filters), "Bad filters")

	const snapshot = table.create(#filters)
	for index, filter in filters do
		snapshot[index] = ServerListFilters.new(filter.name, filter.option)
	end
	return table.freeze(snapshot) :: { FilterDescriptor }
end

--[=[
	Applies all predicates before deterministic sorting. `Recent` includes servers
	started within the configured window and sorts newest-first.

	@within ServerListFilters
	@param servers { ServerMetadata }
	@param filters { FilterDescriptor }
	@return { ServerMetadata }
]=]
function ServerListFilters.apply(servers: { ServerMetadata }, filters: { FilterDescriptor }): { ServerMetadata }
	assert(t.array(ServerListUtils.isServerMetadata)(servers), "Bad servers")
	assert(ServerListFilters.isFilterArray(filters), "Bad filters")

	local ordering: Ordering = "Recent"
	for _, filter in filters do
		if isOrdering(filter.name) then
			ordering = filter.name :: Ordering
		end
	end

	const now = os.time()
	const results = TableUtils.filter(servers, function(metadata: ServerMetadata): boolean
		for _, filter in filters do
			if
				filter.name == "Recent"
				and metadata.startedAt + ServerListConstants.RECENT_SERVER_WINDOW_SECONDS < now
			then
				return false
			elseif filter.name == "Available" and metadata.playerCount >= metadata.maxPlayers then
				return false
			elseif filter.name == "NotEmpty" and metadata.playerCount == 0 then
				return false
			elseif filter.name == "Region" and metadata.region ~= filter.option then
				return false
			end
		end
		return true
	end)

	table.sort(results, function(left: ServerMetadata, right: ServerMetadata): boolean
		if ordering == "MostPlayers" and left.playerCount ~= right.playerCount then
			return left.playerCount > right.playerCount
		elseif ordering == "LeastPlayers" and left.playerCount ~= right.playerCount then
			return left.playerCount < right.playerCount
		end
		return compareRecent(left, right)
	end)
	return ServerListUtils.createSnapshot(results)
end

return ServerListFilters
