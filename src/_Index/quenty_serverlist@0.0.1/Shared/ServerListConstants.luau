--!strict
--[=[
	Configures the place-scoped server directory.

	@within ServerListService
]=]
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")

return TableUtils.deepReadonly({
	MAP_VERSION = 1,
	MAP_NAME_PREFIX = "ServerList",
	NETWORK_NAMESPACE = "ServerList",

	PUBLISH_INTERVAL_SECONDS = 60,
	REFRESH_INTERVAL_SECONDS = 60,
	ENTRY_TTL_SECONDS = 45,
	MAX_CLOCK_SKEW_SECONDS = 30,
	RECENT_SERVER_WINDOW_SECONDS = 300,
	MAX_VISIBLE_SERVERS = 200,
	MEMORY_STORE_PAGE_SIZE = 100,
	MAX_MEMORY_STORE_PAGES = 2,
	MAX_FILTERS = 16,

	LISTED_SERVER_TYPES = {
		"standard",
	},

	USE_NUMERIC_NAME_SUFFIX = true,
	NUMERIC_NAME_SUFFIX_MODULUS = 100,

	MAX_JOB_ID_LENGTH = 128,
	MAX_NAME_LENGTH = 64,
	MAX_REGION_LENGTH = 64,
	MAX_UINT16 = 65535,
	MAX_UINT32 = 4294967295,
	MAX_SAFE_INTEGER = 9007199254740991,

	REQUEST_RATE_LIMIT_CAPACITY = 8,
	REQUEST_RATE_LIMIT_REFILL_RATE = 2,

	NAME_DESCRIPTORS = {
		"Amber",
		"Brisk",
		"Calm",
		"Clever",
		"Flying",
		"Golden",
		"Merry",
		"Quiet",
		"Swift",
	},
	NAME_NOUNS = {
		"Badger",
		"Falcon",
		"Harbor",
		"Horse",
		"Meadow",
		"Otter",
		"Pine",
		"Summit",
		"Willow",
	},
})
