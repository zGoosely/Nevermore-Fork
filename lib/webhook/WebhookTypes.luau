--!strict
--[=[
	Defines typed outbound webhook payloads and responses.

	@types WebhookTypes
	@server
]=]

export type EmbedField = {
	Name: string,
	Value: string,
	Inline: boolean?,
}

export type EmbedFooter = {
	Text: string,
	IconUrl: string?,
}

export type EmbedImage = {
	Url: string,
}

export type EmbedThumbnail = {
	Url: string,
}

export type EmbedAuthor = {
	Name: string,
	Url: string?,
	IconUrl: string?,
}

export type Embed = {
	Title: string?,
	Description: string?,
	Url: string?,
	Timestamp: DateTime?,
	Color: Color3?,
	Footer: EmbedFooter?,
	Image: EmbedImage?,
	Thumbnail: EmbedThumbnail?,
	Author: EmbedAuthor?,
	Fields: { EmbedField }?,
}

export type MessageOptions = {
	Content: string?,
	Embeds: { Embed }?,
	UseTTS: boolean?,
	UsernameOverride: string?,
	AvatarOverride: string?,
	Flags: number?,
	ThreadName: string?,
	WaitForMessage: boolean?,
}

export type WebhookClientOptions = {
	WebhookUrlSecretKey: string,
	ProxyUrl: string?,
	UseProxy: boolean?,
	UseProxyQueue: boolean?,
	MaxPendingRequests: number?,
}

export type WebhookResponse = {
	Success: boolean,
	StatusCode: number,
	StatusMessage: string,
	Headers: { [string]: string },
	Body: string,
}

return {}
