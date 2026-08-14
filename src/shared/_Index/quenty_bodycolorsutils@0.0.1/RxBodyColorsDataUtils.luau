--!strict
--[=[
	Observes body-color data stored as attributes.

	@util RxBodyColorsDataUtils
]=]

const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const Rx = require("@game/ReplicatedStorage/Packages/Rx")
const RxAttributeUtils = require("@game/ReplicatedStorage/Packages/RxAttributeUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

const BodyColorsDataConstants = require("./BodyColorsDataConstants")
const BodyColorsDataUtils = require("./BodyColorsDataUtils")

const RxBodyColorsDataUtils = {}

--[=[
	Observes body-color data stored on an instance's attributes.

	@within RxBodyColorsDataUtils
	@param instance Instance
	@return Observable<BodyColorsData>
]=]
function RxBodyColorsDataUtils.observeFromAttributes(
	instance: Instance
): Observable.Observable<BodyColorsDataUtils.BodyColorsData>
	assert(t.Instance(instance), "Bad instance")
	const observables = {}
	for key, attributeName in BodyColorsDataConstants.ATTRIBUTE_MAPPING do
		observables[key] = RxAttributeUtils.observeAttribute(instance, attributeName)
	end

	return (Rx.combineLatest(observables) :: any):Pipe({
		Rx.map(function(latestValues): BodyColorsDataUtils.BodyColorsData
			const bodyColorsData = {} :: BodyColorsDataUtils.BodyColorsData
			for key, attributeName in BodyColorsDataConstants.ATTRIBUTE_MAPPING do
				const value = latestValues[key]
				if value == nil or t.Color3(value) then
					(bodyColorsData :: any)[key] = value
				else
					warn(`[RxBodyColorsDataUtils] Attribute {attributeName} is not a Color3`)
				end
			end
			return BodyColorsDataUtils.createBodyColorsData(bodyColorsData)
		end),
	}) :: any
end

return RxBodyColorsDataUtils
