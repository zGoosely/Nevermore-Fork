--!strict
--[=[
	Compatibility alias for [PlayerInputActorModel].

	@class PlayerInputServerModel
	@server
]=]
const PlayerInputActorModel = require("./PlayerInputActorModel")

export type PlayerInputServerModel = PlayerInputActorModel.PlayerInputActorModel

return PlayerInputActorModel
