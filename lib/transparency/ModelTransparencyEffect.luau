--!nonstrict
--[=[
	Allows a model to have transparent set locally on the client.

	Supports all BasePart types including:
	- Part
	- MeshPart
	- UnionOperation
	- TrussPart
	- WedgePart
	- CornerWedgePart

	Also supports Decals.

	Can optionally disable visual effects like ParticleEmitters, Lights, Beams, etc.

	@client
	@class ModelTransparencyEffect
]=]

const require = require("../Loader").load()

local BaseObject = require("BaseObject")
local ServiceBag = require("ServiceBag")
local Spring = require("Spring")
local StepUtils = require("StepUtils")
local TransparencyService = require("TransparencyService")

local ModelTransparencyEffect = setmetatable({}, BaseObject)
ModelTransparencyEffect.ClassName = "ModelTransparencyEffect"
ModelTransparencyEffect.__index = ModelTransparencyEffect

export type TransparencyMode = "SetTransparency" | "SetLocalTransparencyModifier"

export type ModelTransparencyEffect =
	typeof(setmetatable(
		{} :: {
			_serviceBag: ServiceBag.ServiceBag,
			_transparency: Spring.Spring<any>,
			_transparencyService: TransparencyService.TransparencyService,
			_transparencyServiceMethodName: TransparencyMode,
			_parts: { [Instance]: boolean },
			_visualEffects: { [Instance]: { enabled: boolean, brightness: number? } }?,
			_disableVisualEffects: boolean,
			_startAnimation: (self: ModelTransparencyEffect) -> (),
		},
		{} :: typeof({ __index = ModelTransparencyEffect })
	))
	& BaseObject.BaseObject<Model>

--[=[
	@param serviceBag ServiceBag
	@param adornee Instance
	@param transparencyServiceMethodName "SetTransparency" | "SetLocalTransparencyModifier" | nil
	@param disableVisualEffects boolean? -- Whether to disable ParticleEmitters, Lights, Beams, etc.
	@return ModelTransparencyEffect
]=]
function ModelTransparencyEffect.new(
	serviceBag: ServiceBag.ServiceBag,
	adornee: Instance,
	transparencyServiceMethodName: TransparencyMode?,
	disableVisualEffects: boolean?
): ModelTransparencyEffect
	local self: ModelTransparencyEffect = setmetatable(BaseObject.new(adornee) :: any, ModelTransparencyEffect)
	self._serviceBag = assert(serviceBag, "No serviceBag")

	assert(
		type(transparencyServiceMethodName) == "string" or transparencyServiceMethodName == nil,
		"Bad transparencyServiceMethodName"
	)

	self._transparencyService = self._serviceBag:GetService(TransparencyService)
	self._transparency = Spring.new(0) -- Start at 0 transparency
	self._transparencyServiceMethodName = transparencyServiceMethodName or "SetTransparency"
	self._disableVisualEffects = disableVisualEffects == true

	self._startAnimation, self._maid._stop = StepUtils.bindToRenderStep(self._update)

	return self
end

--[=[
	Sets the spring speed (how fast it animates)
	@param speed number
]=]
function ModelTransparencyEffect.SetSpeed(self: ModelTransparencyEffect, speed: number)
	self._transparency.s = speed
end

--[=[
	Sets the spring damper (how bouncy/smooth it is)
	@param damper number
]=]
function ModelTransparencyEffect.SetDamper(self: ModelTransparencyEffect, damper: number)
	self._transparency.d = damper
end

--[=[
	Sets the acceleration (deprecated - use SetSpeed instead)
	@param acceleration number
	@deprecated
]=]
function ModelTransparencyEffect.SetAcceleration(self: ModelTransparencyEffect, acceleration: number)
	-- Convert acceleration to spring speed (rough approximation)
	self._transparency.s = math.sqrt(acceleration)
end

--[=[
	Sets the transparency
	@param transparency number
	@param doNotAnimate boolean?
]=]
function ModelTransparencyEffect.SetTransparency(
	self: ModelTransparencyEffect,
	transparency: number,
	doNotAnimate: boolean?
)
	if self._transparency.t == transparency then
		return
	end

	self._transparency.t = transparency
	if doNotAnimate then
		self._transparency.p = self._transparency.t
		self._transparency.v = 0
	end

	self:_startAnimation()
end

--[=[
	Returns true if animation is done
	@return boolean
]=]
function ModelTransparencyEffect.IsDoneAnimating(self: ModelTransparencyEffect): boolean
	return math.abs(self._transparency.p - self._transparency.t) < 0.01 and math.abs(self._transparency.v) < 0.01
end

--[=[
	Finishes the transparency animation, and then calls the callback to
	finish the animation.
	@param callback function
]=]
function ModelTransparencyEffect.FinishTransparencyAnimation(self: ModelTransparencyEffect, callback)
	self:SetTransparency(0)

	if self:IsDoneAnimating() then
		callback()
	else
		-- Wait for spring to settle
		local connection
		connection = self._maid:Add(task.spawn(function()
			while not self:IsDoneAnimating() do
				task.wait(0.1)
			end
			if connection then
				callback()
			end
		end))
	end
end

function ModelTransparencyEffect._update(self: ModelTransparencyEffect): boolean
	if self._transparencyService:IsDead() then
		return false
	end

	local transparency = self._transparency.p
	local lastTransparency = self._lastTransparency or 0

	-- Only update if transparency changed significantly (optimization)
	local transparencyChanged = math.abs(transparency - lastTransparency) > 0.001
	local isAnimating = not self:IsDoneAnimating()

	if transparencyChanged then
		-- Cache parts set to avoid repeated calls
		local partsSet = self:_getPartsSet()

		-- Batch update part transparency
		for part in partsSet do
			self._transparencyService[self._transparencyServiceMethodName](
				self._transparencyService,
				self,
				part,
				transparency
			)
		end

		-- Update visual effects based on transparency (only when transparency changes)
		if self._disableVisualEffects then
			self:_updateVisualEffects(transparency)
		end

		self._lastTransparency = transparency
	end

	-- Stop render step binding when animation is done (optimization)
	if not isAnimating then
		return false -- This will stop the StepUtils binding
	end

	return true -- Continue animating
end

function ModelTransparencyEffect._updateVisualEffects(self: ModelTransparencyEffect, transparency: number)
	local visualEffects = self:_getVisualEffectsSet()
	local shouldDisable = transparency > 0.5 -- Disable when more than 50% transparent

	-- Cache the transparency calculation for brightness effects
	local brightnessMultiplier = 1 - transparency

	for effect, originalState in visualEffects do
		local effectType = effect.ClassName

		-- Use ClassName for faster type checking than IsA
		if
			effectType == "ParticleEmitter"
			or effectType == "Fire"
			or effectType == "Smoke"
			or effectType == "Sparkles"
			or effectType == "Trail"
		then
			effect.Enabled = shouldDisable and false or originalState.enabled
		elseif effectType == "Light" or effectType == "Beam" then
			effect.Enabled = shouldDisable and false or originalState.enabled
			if originalState.brightness and not shouldDisable then
				effect.Brightness = originalState.brightness * brightnessMultiplier
			elseif originalState.brightness and shouldDisable then
				effect.Brightness = 0
			end
		end
	end
end

function ModelTransparencyEffect._getPartsSet(self: ModelTransparencyEffect)
	if self._parts then
		return self._parts
	end

	self:_setupParts()

	return self._parts
end

function ModelTransparencyEffect._getVisualEffectsSet(self: ModelTransparencyEffect)
	if not self._disableVisualEffects then
		return {}
	end

	if self._visualEffects then
		return self._visualEffects
	end

	self:_setupVisualEffects()

	return self._visualEffects
end

function ModelTransparencyEffect._setupParts(self: ModelTransparencyEffect)
	assert(not (self :: any)._parts, "Already initialized")

	self._parts = {}

	if self._obj:IsA("BasePart") or self._obj:IsA("Decal") then
		self._parts[self._obj] = true
	end

	for _, part in self._obj:GetDescendants() do
		if part:IsA("BasePart") or part:IsA("Decal") then
			self._parts[part] = true
		end
	end

	self._maid:GiveTask(self._obj.DescendantAdded:Connect(function(child)
		if child:IsA("BasePart") or child:IsA("Decal") then
			self._parts[child] = true
			self:_startAnimation()
		end
	end))

	self._maid:GiveTask(self._obj.DescendantRemoving:Connect(function(child)
		if self._transparencyService:IsDead() then
			return
		end

		if self._parts[child] then
			self._parts[child] = nil
			self._transparencyService[self._transparencyServiceMethodName](self._transparencyService, self, child, nil)
		end
	end))

	self._maid:GiveTask(function()
		if self._transparencyService:IsDead() then
			return
		end

		for part, _ in self._parts do
			self._transparencyService[self._transparencyServiceMethodName](self._transparencyService, self, part, nil)
		end
	end)
end

function ModelTransparencyEffect._setupVisualEffects(self: ModelTransparencyEffect)
	if not self._disableVisualEffects then
		return
	end

	assert(not self._visualEffects, "Visual effects already initialized")

	self._visualEffects = {}

	-- Store original states of visual effects
	local function storeEffectState(effect)
		local state = { enabled = effect.Enabled }

		-- Store brightness for lights and beams
		if effect:IsA("Light") or effect:IsA("Beam") then
			state.brightness = effect.Brightness
		end

		self._visualEffects[effect] = state
	end

	-- Check root object
	if self:_isVisualEffect(self._obj) then
		storeEffectState(self._obj)
	end

	-- Check descendants
	for _, descendant in self._obj:GetDescendants() do
		if self:_isVisualEffect(descendant) then
			storeEffectState(descendant)
		end
	end

	-- Handle new visual effects added
	self._maid:GiveTask(self._obj.DescendantAdded:Connect(function(child)
		if self:_isVisualEffect(child) then
			storeEffectState(child)
			self:_startAnimation() -- Update effects immediately
		end
	end))

	-- Handle visual effects removed
	self._maid:GiveTask(self._obj.DescendantRemoving:Connect(function(child)
		if self._visualEffects[child] then
			-- Restore original state before removal
			local originalState = self._visualEffects[child]
			if
				child:IsA("ParticleEmitter")
				or child:IsA("Light")
				or child:IsA("Beam")
				or child:IsA("Fire")
				or child:IsA("Smoke")
				or child:IsA("Sparkles")
				or child:IsA("Trail")
			then
				child.Enabled = originalState.enabled
				if originalState.brightness and (child:IsA("Light") or child:IsA("Beam")) then
					child.Brightness = originalState.brightness
				end
			end
			self._visualEffects[child] = nil
		end
	end))

	-- Cleanup: restore all visual effects
	self._maid:GiveTask(function()
		for effect, originalState in self._visualEffects do
			if effect.Parent then
				effect.Enabled = originalState.enabled
				if originalState.brightness and (effect:IsA("Light") or effect:IsA("Beam")) then
					effect.Brightness = originalState.brightness
				end
			end
		end
	end)
end

function ModelTransparencyEffect._isVisualEffect(self: ModelTransparencyEffect, instance: Instance): boolean
	local className = instance.ClassName
	return className == "ParticleEmitter"
		or className == "Light"
		or className == "Beam"
		or className == "Fire"
		or className == "Smoke"
		or className == "Sparkles"
		or className == "Trail"
end

return ModelTransparencyEffect
