--!strict
--[=[
	Shared server-directory contracts.

	@types ServerListTypes
]=]

export type RegionSource = "configured" | "audience" | "external" | "unknown"
export type ServerType = "standard" | "vip" | "reserved"
export type FilterName = "Recent" | "Available" | "NotEmpty" | "Region" | "MostPlayers" | "LeastPlayers"

export type ServerMetadata = {
	jobId: string,
	placeId: number,
	name: string,
	region: string?,
	regionSource: RegionSource,
	playerCount: number,
	maxPlayers: number,
	serverType: ServerType,
	placeVersion: number,
	startedAt: number,
	updatedAt: number,
}

export type FilterDescriptor = {
	name: FilterName,
	option: string?,
}

return {}
