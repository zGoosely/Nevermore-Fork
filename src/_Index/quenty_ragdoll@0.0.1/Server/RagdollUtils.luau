--!strict
--[=[
	Provides a small character-facing facade over Nevermore's Ragdoll binder.

	@util RagdollUtils
	@server
]=]
const cancellableDelay = require("@game/ReplicatedStorage/Packages/cancellableDelay")
const Ragdoll = require("./Classes/Ragdoll")
const t = require("@game/ReplicatedStorage/Packages/t")

const TIMER_TOKEN_ATTRIBUTE = "RagdollUtilsTimerToken"

local RagdollUtils = {}

local function getHumanoid(character: Model): Humanoid
	const humanoid = character:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "Character has no Humanoid")
	return humanoid
end

local function nextTimerToken(character: Model): number
	const current = character:GetAttribute(TIMER_TOKEN_ATTRIBUTE)
	const token = if t.number(current) then (current :: number) + 1 else 1
	character:SetAttribute(TIMER_TOKEN_ATTRIBUTE, token)
	return token
end

local function scheduleUnragdoll(character: Model, humanoid: Humanoid, duration: number): ()
	const token = nextTimerToken(character)
	cancellableDelay(duration, function()
		if character.Parent and character:GetAttribute(TIMER_TOKEN_ATTRIBUTE) == token and Ragdoll:HasTag(humanoid) then
			Ragdoll:Unbind(humanoid)
			character:SetAttribute(TIMER_TOKEN_ATTRIBUTE, nil)
		end
	end)
end

--[=[
	Ragdolls a character and optionally restores it after a duration.

	@within RagdollUtils
	@param character Model
	@param duration number? -- Seconds before restoring the character
]=]
function RagdollUtils.ragdoll(character: Model, duration: number?): ()
	assert(t.instanceIsA("Model")(character), "Bad character")
	assert(t.optional(t.numberMin(0))(duration) and (duration == nil or duration < math.huge), "Bad duration")

	const humanoid = getHumanoid(character)
	Ragdoll:Tag(humanoid)

	if duration ~= nil then
		scheduleUnragdoll(character, humanoid, duration)
	else
		nextTimerToken(character)
	end
end

--[=[
	Stops ragdolling a character.

	@within RagdollUtils
	@param character Model
]=]
function RagdollUtils.unRagdoll(character: Model): ()
	assert(t.instanceIsA("Model")(character), "Bad character")

	const humanoid = getHumanoid(character)
	nextTimerToken(character)
	Ragdoll:Unbind(humanoid)
	character:SetAttribute(TIMER_TOKEN_ATTRIBUTE, nil)
end

--[=[
	Returns whether a character is currently ragdolled.

	@within RagdollUtils
	@param character Model
	@return boolean
]=]
function RagdollUtils.isRagdolled(character: Model): boolean
	assert(t.instanceIsA("Model")(character), "Bad character")
	return Ragdoll:HasTag(getHumanoid(character))
end

return RagdollUtils
