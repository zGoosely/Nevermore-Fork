--!strict
--[=[
	Shared persisted and network contracts for input-keymap bindings.

	@types InputKeyMapDataStoreServiceTypes
]=]

export type SerializedInputType = {
	Kind: number,
	Name: string,
	Modifiers: { string }?,
}

export type Binding = {
	ProviderName: string,
	ListName: string,
	InputModeName: string,
	InputTypes: { SerializedInputType },
}

export type BindingRequest = Binding & {
	Clear: boolean,
}

export type Bindings = { Binding }

return {}
