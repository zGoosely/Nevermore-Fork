--!strict
--[=[
	Shared internal type contracts for client culling.

	@types ClientCullingTypes
]=]

export type CullMode = "Render" | "Shadows"

export type CullConfig = {
	CullDistance: number,
	UncullDistance: number,
	Dynamic: boolean,
}

export type CullBounds = {
	CFrame: CFrame,
	Size: Vector3,
	Radius: number,
}

export type CullOwner = {
	_adornee: Instance,
}

export type CullEntry = CullOwner & {
	_mode: CullMode,
	_config: CullConfig,
	_bounds: CullBounds,
	_culled: boolean,
	_queryGeneration: number,

	RefreshDynamicBounds: (self: CullEntry) -> boolean,
	SetCulled: (self: CullEntry, culled: boolean) -> (),
}

return {}
