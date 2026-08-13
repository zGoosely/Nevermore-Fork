--!strict
--[=[
	Provides localized strings for game configurations.

	@class GameConfigTranslator
]=]
const JSONTranslator = require("@game/ReplicatedStorage/Packages/JSONTranslator")

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
