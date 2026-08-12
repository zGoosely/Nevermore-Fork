--!strict
--[=[
	Extracts the local character's default Animate configuration without cloning
	a LocalScript into every rendered NPC.

	@util DefaultCharacterAnimationUtils
]=]

const require = require("../../Loader").load()

const Promise = require("Promise")
const RbxAssetUtils = require("RbxAssetUtils")

export type AnimationIds = {
	idleAnimationId: string,
	walkAnimationId: string,
}

const DefaultCharacterAnimationUtils = {}

const function findAnimationId(container: Instance, names: { string }): string?
	for _, name in names do
		const child = container:FindFirstChild(name)
		if child then
			const animation = if child:IsA("Animation") then child else child:FindFirstChildWhichIsA("Animation", true)
			if animation and animation.AnimationId ~= "" then
				return animation.AnimationId
			end
		end
	end
	return nil
end

const function toAssetId(value: number): string
	return if value > 0 then RbxAssetUtils.toRbxAssetId(value) else ""
end

--[=[
	Reads idle and walk animation ids from a standard Roblox `Animate`
	hierarchy. The script itself does not need to run.

	@within DefaultCharacterAnimationUtils
	@param animate Instance
	@return AnimationIds
]=]
function DefaultCharacterAnimationUtils.getAnimationIdsFromAnimate(animate: Instance): AnimationIds
	assert(typeof(animate) == "Instance", "Bad animate")

	return {
		idleAnimationId = findAnimationId(animate, { "idle", "Idle", "Animation1" }) or "",
		walkAnimationId = findAnimationId(animate, { "walk", "Walk", "run", "Run", "WalkAnim", "RunAnim" }) or "",
	}
end

--[=[
	Promises the idle and walk animation ids configured by the local character's
	Animate script, falling back to its applied HumanoidDescription.

	@within DefaultCharacterAnimationUtils
	@param character Model
	@return Promise<AnimationIds>
]=]
function DefaultCharacterAnimationUtils.promiseAnimationIdsAsync(character: Model): Promise.Promise<AnimationIds>
	assert(typeof(character) == "Instance" and character:IsA("Model"), "Bad character")

	return Promise.spawn(function(resolve)
		const animate = character:FindFirstChild("Animate") or character:WaitForChild("Animate", 5)
		local idleAnimationId = ""
		local walkAnimationId = ""
		if animate then
			const animationIds = DefaultCharacterAnimationUtils.getAnimationIdsFromAnimate(animate)
			idleAnimationId = animationIds.idleAnimationId
			walkAnimationId = animationIds.walkAnimationId
		end

		if idleAnimationId == "" or walkAnimationId == "" then
			const humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				const success, description = (pcall :: any)(humanoid.GetAppliedDescription, humanoid)
				if success and typeof(description) == "Instance" and description:IsA("HumanoidDescription") then
					if idleAnimationId == "" then
						idleAnimationId = toAssetId(description.IdleAnimation)
					end
					if walkAnimationId == "" then
						walkAnimationId = toAssetId(
							if description.WalkAnimation > 0
								then description.WalkAnimation
								else description.RunAnimation
						)
					end
				end
			end
		end

		resolve({
			idleAnimationId = idleAnimationId,
			walkAnimationId = walkAnimationId,
		})
	end)
end

return DefaultCharacterAnimationUtils
