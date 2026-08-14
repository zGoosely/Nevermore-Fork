--!strict
--[=[
	Identifies visual effects managed by ModelTransparencyEffect.

	@util ModelTransparencyEffectUtils
]=]

const t = require("@game/ReplicatedStorage/Packages/t")

const ModelTransparencyEffectUtils = {}

--[=[
	Returns whether an instance is a supported visual effect.

	@within ModelTransparencyEffectUtils
	@param instance Instance
	@return boolean
]=]
function ModelTransparencyEffectUtils.isVisualEffect(instance: Instance): boolean
	assert(t.instance(instance), "Bad instance")

	const className = instance.ClassName
	return className == "ParticleEmitter"
		or className == "Light"
		or className == "Beam"
		or className == "Fire"
		or className == "Smoke"
		or className == "Sparkles"
		or className == "Trail"
end

return ModelTransparencyEffectUtils
