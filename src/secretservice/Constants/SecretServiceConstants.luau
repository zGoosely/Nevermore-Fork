--!strict
--[=[
	@class SecretServiceConstants
]=]

const require = require("../../Loader").load()

return require("TableUtils").readonly({
	REQUEST_SECRET_KEY_NAMES_LIST = "requestSecretKeyNamesList",

	DEFAULT_STORE_NAME = "Secrets",
	DEFAULT_STORE_KEY = "Global",
	SECRETS_DATA_KEY = "Secrets",
})
