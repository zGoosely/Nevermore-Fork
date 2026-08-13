--!strict
--[=[
	@class RxPartBoundingBoxUtils
]=]
local Observable = require("@game/ReplicatedStorage/Packages/Observable")
local RxInstanceUtils = require("@game/ReplicatedStorage/Packages/RxInstanceUtils")

local RxPartBoundingBoxUtils = {}

--[=[
	Observes the CFrame of a part

	@param part BasePart
	@return Observable<CFrame>
]=]
function RxPartBoundingBoxUtils.observePartCFrame(part: BasePart): Observable.Observable<CFrame>
	assert(typeof(part) == "Instance" and part:IsA("BasePart"), "Bad part")

	return RxInstanceUtils.observeProperty(part, "CFrame")
end

return RxPartBoundingBoxUtils
