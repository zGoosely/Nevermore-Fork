--!strict
--[=[
	Stateless utility functions for team kill trackers.

	@util TeamKillTrackerUtils
]=]
const BinderUtils = require("@game/ReplicatedStorage/Packages/BinderUtils")
const RxBinderUtils = require("@game/ReplicatedStorage/Packages/RxBinderUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

const TeamKillTrackerUtils = {}

--[=[
	Creates a new TeamKillTracker score IntValue.

	@within TeamKillTrackerUtils
	@param binder any
	@return IntValue
]=]
function TeamKillTrackerUtils.create(binder: any): IntValue
	assert(t.table(binder), "Bad binder")

	const score = Instance.new("IntValue")
	score.Name = "TeamKillTracker"
	score.Value = 0

	binder:Bind(score)

	return score
end

--[=[
	Observes bound child class Brio for the team instance.

	@within TeamKillTrackerUtils
	@param binder any
	@param instance Instance
	@return Observable<Brio<any>>
]=]
function TeamKillTrackerUtils.observeBrio(binder: any, instance: Instance): any
	assert(t.table(binder), "Bad binder")
	assert(t.Instance(instance), "Bad instance")

	return RxBinderUtils.observeBoundChildClassBrio(binder, instance)
end

--[=[
	Gets the first bound team kill tracker child under parent.

	@within TeamKillTrackerUtils
	@param binder any
	@param team Instance
	@return any
]=]
function TeamKillTrackerUtils.getTeamKillTracker(binder: any, team: Instance): any
	assert(t.table(binder), "Bad binder")
	assert(t.Instance(team), "Bad team")

	return BinderUtils.findFirstChild(binder, team)
end

return TeamKillTrackerUtils
