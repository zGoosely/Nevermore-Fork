--!strict
--[=[
	Scale ratios for the UI on different devices
	@class GuiScalingUtils
]=]

local GuiService = game:GetService('GuiService')

const require = require("../Loader").load()

local Maid = require('Maid')
local Observable = require('Observable')
local ObservableInstance = require('ObservableInstance')
local Rx = require('Rx')
local RxAttributeUtils = require('RxAttributeUtils')
local RxCollectionServiceUtils = require('RxCollectionServiceUtils')
local RxInstanceUtils = require('RxInstanceUtils')
local SpringObject = require('SpringObject')
local ValueObject = require('ValueObject')

local PHONE_HEIGHT = 393
local PC_HEIGHT = 1080
local SCALE_TAG_NAME = 'UIScale'
local MINIMUM_SCALE_ATTR_NAME = 'PaneMinimumScale'
local MAXIMUM_SCALE_ATTR_NAME = 'PaneMaximumScale'

local Camera = workspace.CurrentCamera :: Camera

local GuiScalingUtils = {}

GuiScalingUtils.ObservedListScales = {}
GuiScalingUtils.DefaultMinimumScale = ValueObject.new(0.75 :: number, 'number')
GuiScalingUtils.DefaultMaximumScale = ValueObject.new(1 :: number, 'number')
GuiScalingUtils._currentUIScaleAlpha = ValueObject.new(1 :: number, 'number')

local function getViewportAlpha(viewportSize: number): number
	return math.clamp((viewportSize - PHONE_HEIGHT) / (PC_HEIGHT - PHONE_HEIGHT), 0, 1)
end

export type UIScaleInfo = {
	value: UIScale,
	minimumScale: number,
	maximumScale: number,
}

--[=[
	Given an screenAbsoluteSize, get a good UI scale to use for fixed offset
	assuming general UI scales built for 720p monitors.

	@param screenAbsoluteSize Vector2
	@return number
]=]
function GuiScalingUtils.getUIScale(screenAbsoluteSize: Vector2): number
	assert(typeof(screenAbsoluteSize) == 'Vector2', 'Bad screenAbsoluteSize')
	local smallestAxis = math.min(screenAbsoluteSize.X, screenAbsoluteSize.Y)
	local height = screenAbsoluteSize.Y

	if GuiService:IsTenFootInterface() then
		return 2
	elseif smallestAxis >= 900 then
		return 1.5
	elseif smallestAxis >= 700 then
		return 1.25
	elseif height >= 500 then
		return 1
	elseif height >= 325 then
		return 0.75
	else
		return 0.6
	end
end

--[=[
	Observes a smoothed out UI scale for a given screenGui
	@param screenGui ScreenGui
	@return Observable<number>
]=]
function GuiScalingUtils.observeUIScale(
	screenGui: ScreenGui
): Observable.Observable<number>
	return Observable.new(function(sub)
		local maid = Maid.new()

		-- Create a SpringObject to animate the scale
		local spring = maid:Add(
			SpringObject.new(GuiScalingUtils.getUIScale(screenGui.AbsoluteSize), 30)
		)

		-- Observe spring changes
		maid:GiveTask(spring:Observe():Subscribe(function(value)
			sub:Fire(value)
		end))

		-- Observe absolute size and update spring target
		maid:GiveTask(
			RxInstanceUtils.observeProperty(screenGui, 'AbsoluteSize')
				:Subscribe(function(size)
					local targetScale = GuiScalingUtils.getUIScale(size)
					spring:SetTarget(targetScale)
				end)
		)

		return maid
	end)
end

--[=[
	Observes a smoothed out UI scale for a given screenGui
	@param child Instance
	@return Observable<number>
]=]
function GuiScalingUtils.observeUIScaleForChild(
	child: Instance
): Observable.Observable<number>
	return RxInstanceUtils.observeFirstAncestor(child, 'ScreenGui'):Pipe({
		Rx.switchMap(function(screenGui: ScreenGui?): any
			if screenGui then
				return GuiScalingUtils.observeUIScale(screenGui)
			else
				return Rx.EMPTY
			end
		end) :: any,
	}) :: any
end

--[=[
	Creates a UIScale instance with automatic scaling

	@param parent Instance?
	@param screenGui ScreenGui
	@return ObservableInstance
]=]
function GuiScalingUtils.createUIScale(
	parent: Instance?,
	screenGui: ScreenGui
): ObservableInstance.ObservableInstance
	assert(screenGui, 'No screenGui')

	-- Create ObservableInstance for UIScale
	local uiScale = ObservableInstance.new('UIScale', {
		Scale = GuiScalingUtils.getUIScale(screenGui.AbsoluteSize),
	})

	local maid = Maid.new()

	local spring = maid:Add(SpringObject.new(uiScale:GetValue('Scale'), 10, 1))
	maid:GiveTask(spring:Observe():Subscribe(function(scale)
		uiScale:SetValue('Scale', scale)
	end))

	maid:GiveTask(
		RxInstanceUtils.observeProperty(screenGui, 'AbsoluteSize')
			:Subscribe(function(size)
				spring:SetTarget(GuiScalingUtils.getUIScale(size))
			end)
	)

	local instance = uiScale:GetInstance()
	instance.Parent = parent

	maid:GiveTask(instance.Destroying:Connect(function()
		maid:Destroy()
	end))

	return uiScale
end

--[=[
	Creates a UIPadding instance with automatic dialog padding

	@param parent Instance?
	@param screenGui ScreenGui
	@return ObservableInstance
]=]
function GuiScalingUtils.createDialogPadding(
	parent: Instance?,
	screenGui: ScreenGui
): ObservableInstance.ObservableInstance
	assert(screenGui, 'No screenGui')

	local initialPadding = GuiScalingUtils.getDialogPadding(screenGui.AbsoluteSize)
	local uiPadding = ObservableInstance.new('UIPadding', {
		PaddingTop = UDim.new(0, initialPadding),
		PaddingBottom = UDim.new(0, initialPadding),
		PaddingLeft = UDim.new(0, initialPadding),
		PaddingRight = UDim.new(0, initialPadding),
	})

	local maid = Maid.new()
	local spring = maid:Add(SpringObject.new(initialPadding, 30))

	-- Observe spring and update UIPadding
	maid:GiveTask(spring:Observe():Subscribe(function(padding)
		local udim = UDim.new(0, padding)
		uiPadding:SetProperties({
			PaddingTop = udim,
			PaddingBottom = udim,
			PaddingLeft = udim,
			PaddingRight = udim,
		})
	end))

	-- Observe screen size changes
	maid:GiveTask(
		RxInstanceUtils.observeProperty(screenGui, 'AbsoluteSize')
			:Subscribe(function(size)
				local targetPadding = GuiScalingUtils.getDialogPadding(size)
				spring:SetTarget(targetPadding)
			end)
	)

	local instance = uiPadding:GetInstance()
	instance.Parent = parent

	maid:GiveTask(instance.Destroying:Connect(function()
		maid:Destroy()
	end))

	return uiPadding
end

--[=[
	Observes a smoothed out dialog padding for a given screenGui
	@param screenGui ScreenGui
	@return Observable<UDim>
]=]
function GuiScalingUtils.observeDialogPadding(
	screenGui: ScreenGui
): Observable.Observable<UDim>
	return Observable.new(function(sub)
		local maid = Maid.new()

		-- Create a SpringObject to animate the padding
		local spring = maid:Add(
			SpringObject.new(GuiScalingUtils.getDialogPadding(screenGui.AbsoluteSize), 30)
		)

		-- Observe spring changes and emit as UDim
		maid:GiveTask(spring:Observe():Subscribe(function(value)
			sub:Fire(UDim.new(0, value))
		end))

		-- Observe absolute size and update spring target
		maid:GiveTask(
			RxInstanceUtils.observeProperty(screenGui, 'AbsoluteSize')
				:Subscribe(function(size)
					local targetPadding = GuiScalingUtils.getDialogPadding(size)
					spring:SetTarget(targetPadding)
				end)
		)

		return maid
	end)
end

--[=[
	Computes a reasonable dialog padding for a given absolute screen size
	@param screenAbsoluteSize Vector2
	@return number
]=]
function GuiScalingUtils.getDialogPadding(screenAbsoluteSize: Vector2): number
	assert(typeof(screenAbsoluteSize) == 'Vector2', 'Bad screenAbsoluteSize')
	local smallestAxis = math.min(screenAbsoluteSize.X, screenAbsoluteSize.Y)

	if smallestAxis <= 300 then
		return 5
	elseif smallestAxis <= 500 then
		return 10
	elseif smallestAxis <= 700 then
		return 25
	else
		return 50
	end
end

function GuiScalingUtils.observeUIScalesInternally()
	RxCollectionServiceUtils.observeTaggedBrio(SCALE_TAG_NAME)
		:Pipe({
			Rx.switchMap(function(brio)
				local value = brio:GetValue()
				local maid = brio:ToMaid()

				return Rx.combineLatest({
					minimumScale = RxAttributeUtils.observeAttribute(
						value,
						MINIMUM_SCALE_ATTR_NAME,
						GuiScalingUtils.DefaultMinimumScale.Value
					),
					maximumScale = RxAttributeUtils.observeAttribute(
						value,
						MAXIMUM_SCALE_ATTR_NAME,
						GuiScalingUtils.DefaultMaximumScale.Value
					),
					defaultMin = GuiScalingUtils.DefaultMinimumScale:Observe(),
					defaultMax = GuiScalingUtils.DefaultMaximumScale:Observe(),
					viewportAlpha = GuiScalingUtils._currentUIScaleAlpha:Observe(),
				}):Pipe({
					Rx.map(function(attributes)
						return {
							minimumScale = attributes.minimumScale,
							maximumScale = attributes.maximumScale,
							viewportAlpha = attributes.viewportAlpha,
							value = value :: UIScale,
							maid = maid,
						}
					end),
				})
			end),
		})
		:Subscribe(function(info: UIScaleInfo & { maid: any, viewportAlpha: number })
			GuiScalingUtils.ObservedListScales[info.value] = info

			info.maid:GiveTask(function()
				GuiScalingUtils.ObservedListScales[info.value] = nil
			end)

			local uiScaleAlpha: number =
				math.map(info.viewportAlpha, 0, 1, info.minimumScale, info.maximumScale)
			info.value.Scale = uiScaleAlpha
		end)

	RxInstanceUtils.observeProperty(Camera, 'ViewportSize')
		:Pipe({ Rx.distinct() })
		:Subscribe(function(viewportSize)
			GuiScalingUtils._currentUIScaleAlpha.Value = getViewportAlpha(viewportSize.Y)
		end)
end

GuiScalingUtils.observeUIScalesInternally()

return GuiScalingUtils
