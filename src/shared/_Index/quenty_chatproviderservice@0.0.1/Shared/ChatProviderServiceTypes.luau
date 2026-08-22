--!strict
--[=[
	Shared chat tag data types.

	@types ChatProviderServiceTypes
]=]

export type ChatTag = {
	Id: string,
	Text: string,
	Order: number,
	Color: Color3,
	Enabled: boolean,
}

export type ChatTagInput = {
	Id: string,
	Text: string,
	Order: number?,
	Color: Color3?,
	Enabled: boolean?,
}

return {}
