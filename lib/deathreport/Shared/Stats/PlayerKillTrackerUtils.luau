--!strict
--[=[
	Stateless utility functions for player kill trackers.

	@util PlayerKillTrackerUtils
]=]

const require = require("../../../Loader").load()

const BinderUtils = require("BinderUtils")
const RxBinderUtils = require("RxBinderUtils")
const t = require("t")

const PlayerKillTrackerUtils = {}

--[=[
	Creates a new PlayerKillTracker score IntValue bound to the player.

	@within PlayerKillTrackerUtils
	@param binder any
	@param player Player
	@return IntValue
]=]
function PlayerKillTrackerUtils.create(binder: any, player: Player): IntValue
	assert(t.table(binder), "Bad binder")
	assert(t.instanceIsA("Player")(player), "Bad player")

	const score = Instance.new("IntValue")
	score.Name = "PlayerKillTracker"
	score.Value = 0

	binder:Bind(score)
	score.Parent = player

	return score
end

--[=[
	Observes bound child class Brio for the player.

	@within PlayerKillTrackerUtils
	@param binder any
	@param player Player
	@return Observable<Brio<any>>
]=]
function PlayerKillTrackerUtils.observeBrio(binder: any, player: Player): any
	assert(t.table(binder), "Bad binder")
	assert(t.instanceIsA("Player")(player), "Bad player")

	return RxBinderUtils.observeBoundChildClassBrio(binder, player)
end

--[=[
	Gets the first bound player kill tracker child under parent.

	@within PlayerKillTrackerUtils
	@param binder any
	@param parent Instance
	@return any
]=]
function PlayerKillTrackerUtils.getPlayerKillTracker(binder: any, parent: Instance): any
	assert(t.table(binder), "Bad binder")
	assert(t.instance(parent), "Bad parent")

	return BinderUtils.findFirstChild(binder, parent)
end

return PlayerKillTrackerUtils
