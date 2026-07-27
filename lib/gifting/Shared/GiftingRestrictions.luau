--!strict
--[=[
	Controls who a player may gift.

	@class GiftingRestrictions
]=]

const require = require("../../Loader").load()

const Enums = require("Enums")

export type GiftingRestriction = "all" | "friends"

return Enums.new({
	All = "all" :: "all",
	Friends = "friends" :: "friends",
	ALL = "all" :: "all",
	FRIENDS = "friends" :: "friends",
})
