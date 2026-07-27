--!strict
--[=[
	Provides localized strings for game configurations.

	@class GameConfigTranslator
]=]

const require = require("../../Loader").load()

const JSONTranslator = require("JSONTranslator")

return JSONTranslator.new("GameConfigTranslator", "en", {
	assets = {
		name = {
			unknown = "???",
		},
		description = {
			unknown = "???",
		},
	},
})
