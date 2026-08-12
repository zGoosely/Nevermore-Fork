--!strict
--[=[
	Roguelike properties applied to humanoids.

	@class RogueHumanoidBase
]=]

const require = require("../../Loader").load()

const RunService = game:GetService("RunService")

const AttributeUtils = require("AttributeUtils")
const BaseObject = require("BaseObject")
const Maid = require("Maid")
const RogueHumanoidProperties = require("RogueHumanoidProperties")
const Rx = require("Rx")
const RxCharacterUtils = require("RxCharacterUtils")
const RxRootPartUtils = require("RxRootPartUtils")
const ServiceBag = require("ServiceBag")
const ValueObject = require("ValueObject")

const GROWTH_VALUE_NAMES: { [string]: true } = {
	HeadScale = true,
	BodyDepthScale = true,
	BodyHeightScale = true,
	BodyWidthScale = true,
}

type ScaleState = {
	scale: number,
	maxSize: number,
	minSize: number,
}

const RogueHumanoidBase = setmetatable({}, BaseObject)
RogueHumanoidBase.ClassName = "RogueHumanoidBase"
RogueHumanoidBase.__index = RogueHumanoidBase

export type RogueHumanoidBase =
	typeof(setmetatable(
		{} :: {
			_obj: Humanoid,
			_serviceBag: ServiceBag.ServiceBag,
			_properties: any,
			_scaleState: ValueObject.ValueObject<ScaleState?>,
		},
		{} :: typeof({ __index = RogueHumanoidBase })
	))
	& BaseObject.BaseObject

function RogueHumanoidBase.new(humanoid: Humanoid, serviceBag: ServiceBag.ServiceBag): RogueHumanoidBase
	const self: RogueHumanoidBase = setmetatable(BaseObject.new(humanoid) :: any, RogueHumanoidBase)

	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._properties = RogueHumanoidProperties:GetPropertyTable(self._serviceBag, self._obj)
	-- On the server this authors every base property before clients add local modifiers.
	self._properties:GetValue()
	self._scaleState = self._maid:Add(ValueObject.fromObservable(Rx.combineLatest({
		scale = self._properties.Scale:Observe(),
		maxSize = self._properties.ScaleMax:Observe(),
		minSize = self._properties.ScaleMin:Observe(),
	})) :: any)

	if RunService:IsClient() then
		self._maid:Add(RxCharacterUtils.observeIsOfLocalCharacterBrio(self._obj):Subscribe(function(brio)
			if brio:IsDead() then
				return
			end

			const maid = brio:ToMaid()
			maid:Add(self._properties.WalkSpeed:Observe():Subscribe(function(walkSpeed)
				self._obj.WalkSpeed = walkSpeed
			end))
			maid:Add(self._properties.CharacterUseJumpPower:Observe():Subscribe(function(useJumpPower)
				self._obj.UseJumpPower = useJumpPower
			end))
			maid:Add(self._properties.JumpPower:Observe():Subscribe(function(jumpPower)
				self._obj.JumpPower = jumpPower
			end))
			maid:Add(self._properties.JumpHeight:Observe():Subscribe(function(jumpHeight)
				self._obj.JumpHeight = jumpHeight
			end))
			self:_setupIgnoreCFrameChangesOnScaleChange(maid)
		end))
	end

	self._maid:Add(self._properties.MaxHealth:Observe():Subscribe(function(maxHealth)
		const newMaxHealth = math.max(maxHealth, 1)
		const currentMaxHealth = self._obj.MaxHealth

		if currentMaxHealth < newMaxHealth then
			const gained = newMaxHealth - currentMaxHealth
			self._obj.MaxHealth = newMaxHealth
			self._obj.Health += gained
		else
			self._obj.MaxHealth = newMaxHealth
			self._obj.Health = math.min(self._obj.Health, newMaxHealth)
		end
	end))

	self:_setupScaling()

	return self
end

function RogueHumanoidBase.CreateMultiplier(
	self: RogueHumanoidBase,
	property: string,
	amount: number,
	source: Instance?
): ValueBase
	const rogueProperty = assert(self._properties:GetRogueProperty(property), "Bad property")
	assert(type(rogueProperty.Value) == "number", "Incompatible property")

	return assert(rogueProperty:CreateMultiplier(amount, source)) :: ValueBase
end

function RogueHumanoidBase.CreateAdditive(
	self: RogueHumanoidBase,
	property: string,
	amount: number,
	source: Instance?
): ValueBase
	const rogueProperty = assert(self._properties:GetRogueProperty(property), "Bad property")
	assert(type(rogueProperty.Value) == "number", "Incompatible property")

	return assert(rogueProperty:CreateAdditive(amount, source)) :: ValueBase
end

function RogueHumanoidBase._setupScaling(self: RogueHumanoidBase): ()
	self._maid:Add(self._scaleState
		:Observe()
		:Pipe({
			Rx.where(function(state)
				return state ~= nil
			end) :: any,
		})
		:Subscribe(function(state)
			self:_updateScale(state)
		end))

	self._maid:Add(self._obj.ChildAdded:Connect(function(child)
		if child:IsA("NumberValue") and GROWTH_VALUE_NAMES[child.Name] then
			const state = self._scaleState.Value
			if state then
				self:_updateScaleValue(child, state)
			end
		end
	end))
end

function RogueHumanoidBase._setupIgnoreCFrameChangesOnScaleChange(self: RogueHumanoidBase, topMaid: Maid.Maid): ()
	topMaid:Add(RxRootPartUtils.observeHumanoidRootPartBrioFromHumanoid(self._obj):Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		const maid, rootPart = brio:ToMaidAndValue()
		local lastSafeRootPartCFrame = rootPart.CFrame
		local rootPartExperiencedTeleport = false

		maid:Add(RunService.PostSimulation:Connect(function()
			lastSafeRootPartCFrame = rootPart.CFrame
			rootPartExperiencedTeleport = false
		end))
		maid:Add(rootPart:GetPropertyChangedSignal("CFrame"):Connect(function()
			rootPartExperiencedTeleport = true
		end))
		maid:Add(rootPart:GetPropertyChangedSignal("Size"):Connect(function()
			rootPartExperiencedTeleport = true
		end))
		maid:Add(self._scaleState.Changed:Connect(function()
			if rootPartExperiencedTeleport then
				rootPart.CFrame = lastSafeRootPartCFrame
			end
		end))
	end))
end

function RogueHumanoidBase._updateScale(self: RogueHumanoidBase, state: ScaleState): ()
	for name in GROWTH_VALUE_NAMES do
		const numberValue = self._obj:FindFirstChild(name)
		if numberValue and numberValue:IsA("NumberValue") then
			self:_updateScaleValue(numberValue, state)
		end
	end
end

function RogueHumanoidBase._updateScaleValue(_self: RogueHumanoidBase, numberValue: NumberValue, state: ScaleState): ()
	const initialValue = AttributeUtils.initAttribute(numberValue, "RogueHumanoid_OriginalValue", numberValue.Value)
	const multiplier = state.minSize
		+ (math.exp(0.07 * state.scale) * (-state.minSize + state.maxSize))
			/ (math.exp(0.07 * state.scale) + (-1 + state.maxSize) / (1 - state.minSize))
	numberValue.Value = if state.scale == 1 then initialValue else initialValue * multiplier
end

return RogueHumanoidBase
