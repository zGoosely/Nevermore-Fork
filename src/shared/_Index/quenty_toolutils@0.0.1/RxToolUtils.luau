--!strict
--[=[
	@class RxToolUtils
]=]
local Brio = require("@game/ReplicatedStorage/Packages/Brio")
local Observable = require("@game/ReplicatedStorage/Packages/Observable")
local RxBrioUtils = require("@game/ReplicatedStorage/Packages/RxBrioUtils")
local RxInstanceUtils = require("@game/ReplicatedStorage/Packages/RxInstanceUtils")

local RxToolUtils = {}

--[=[
	Observes the equipped humanoid of a given tool

	@param tool Instance
	@return Observable<Brio<Humanoid>>
]=]
function RxToolUtils.observeEquippedHumanoidBrio(tool: Tool): Observable.Observable<Brio.Brio<Humanoid>>
	assert(typeof(tool) == "Instance", "Bad tool")

	return RxInstanceUtils.observePropertyBrio(tool, "Parent", function(parent)
		return parent and parent:IsA("Model")
	end):Pipe({
		RxBrioUtils.switchMapBrio(function(parent)
			return RxInstanceUtils.observeChildrenOfClassBrio(parent, "Humanoid")
		end) :: any,
	}) :: any
end

return RxToolUtils
