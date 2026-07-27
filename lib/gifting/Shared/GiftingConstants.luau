--!strict
--[=[
	Shared GiftingService constants.

	@constants GiftingConstants
]=]

return table.freeze({
	ROOT_PATH = "Gifted",
	MAX_GIFT_KEY_LENGTH = 100,
	MAX_METADATA_JSON_LENGTH = 4096,
	MAX_QUANTITY = 1_000_000,
	MAX_PROCESSED_PURCHASES = 256,
	PENDING_PURCHASE_LIFETIME = 15 * 60,
})
