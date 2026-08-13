--!strict
--[=[
	Controls who a player may gift.

	@class GiftingRestrictions
]=]
const Enums = require("@game/ReplicatedStorage/Packages/Enums")

export type GiftingRestriction = "all" | "friends"

return Enums.new({
	All = "all" :: "all",
	Friends = "friends" :: "friends",
	ALL = "all" :: "all",
	FRIENDS = "friends" :: "friends",
})
