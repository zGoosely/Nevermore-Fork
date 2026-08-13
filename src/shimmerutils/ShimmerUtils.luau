--!strict
--[=[
	Attaches a reactive shimmer effect to a GuiObject for the lifetime of a Blend mount.

	Portions of the visual behavior are adapted from Shime 1.0.1 by RyanLua.
	Copyright 2023 RyanLua.

	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at

		https://www.apache.org/licenses/LICENSE-2.0

	Unless required by applicable law or agreed to in writing, software
	distributed under the License is distributed on an "AS IS" BASIS,
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and
	limitations under the License.

	Source: https://github.com/RyanLua/Shime

	@util ShimmerUtils
]=]

const TweenService = game:GetService("TweenService")

const require = require("../Loader").load()

const Maid = require("Maid")
const Observable = require("Observable")
const Rx = require("Rx")
const RxInstanceUtils = require("RxInstanceUtils")
const ValueObject = require("ValueObject")
const t = require("t")

const DEFAULT_DELAY_TIME = 0
const DEFAULT_DURATION = 1
const DEFAULT_POSITION = UDim2.fromScale(0.5, 0.5)
const DEFAULT_SIZE = UDim2.fromScale(1, 1)
const SHIMMER_END_OFFSET = Vector2.new(1, 0)
const SHIMMER_START_OFFSET = Vector2.new(-1, 0)

const function isFiniteNumber(value: any): boolean
	return t.number(value) and value > -math.huge and value < math.huge
end
const isOptions = t.strictInterface({
	DelayTime = t.optional(function(value: any): boolean
		return isFiniteNumber(value) and value >= 0
	end),
	Duration = t.optional(function(value: any): boolean
		return isFiniteNumber(value) and value > 0
	end),
})
const isBooleanMountable = t.union(t.boolean, t.instanceIsA("BoolValue"), function(value: any): boolean
	return Observable.isObservable(value)
end, function(value: any): boolean
	return ValueObject.isValueObject(value)
end)

export type ShimmerOptions = {
	DelayTime: number?,
	Duration: number?,
}

export type ShimmerMountable = ValueObject.Mountable<boolean>

const ShimmerUtils = {}

const function applyDefaultBounds(frame: Frame): ()
	frame.Position = DEFAULT_POSITION
	frame.Size = DEFAULT_SIZE
end

const function updatePaddingBounds(frame: Frame, padding: UIPadding?): ()
	if not padding then
		applyDefaultBounds(frame)
		return
	end

	const widthScale = padding.PaddingLeft.Scale + padding.PaddingRight.Scale
	const heightScale = padding.PaddingTop.Scale + padding.PaddingBottom.Scale
	if widthScale >= 1 or heightScale >= 1 then
		applyDefaultBounds(frame)
		return
	end

	const widthOffset = padding.PaddingLeft.Offset + padding.PaddingRight.Offset
	const heightOffset = padding.PaddingTop.Offset + padding.PaddingBottom.Offset
	const widthDifference = padding.PaddingLeft.Offset - padding.PaddingRight.Offset
	const heightDifference = padding.PaddingTop.Offset - padding.PaddingBottom.Offset

	frame.Size = UDim2.new(1 / (1 - widthScale), widthOffset, 1 / (1 - heightScale), heightOffset)
	frame.Position = UDim2.new(0.5, -widthDifference / 2, 0.5, -heightDifference / 2)
end

const function syncCorner(maid: Maid.Maid, target: GuiObject, frame: Frame): ()
	const cornerMaid = Maid.new()
	maid._corner = cornerMaid

	const targetCorner = target:FindFirstChildOfClass("UICorner")
	if not targetCorner then
		return
	end

	const corner = cornerMaid:Add(Instance.new("UICorner"))
	const function update(): ()
		corner.CornerRadius = targetCorner.CornerRadius
	end

	cornerMaid:Add(targetCorner:GetPropertyChangedSignal("CornerRadius"):Connect(update))
	corner.Parent = frame
	update()
end

const function syncPadding(maid: Maid.Maid, target: GuiObject, frame: Frame): ()
	const paddingMaid = Maid.new()
	maid._padding = paddingMaid

	const padding = target:FindFirstChildOfClass("UIPadding")
	if not padding then
		applyDefaultBounds(frame)
		return
	end

	paddingMaid:Add(Rx.combineLatest({
		bottom = RxInstanceUtils.observeProperty(padding, "PaddingBottom"),
		left = RxInstanceUtils.observeProperty(padding, "PaddingLeft"),
		right = RxInstanceUtils.observeProperty(padding, "PaddingRight"),
		top = RxInstanceUtils.observeProperty(padding, "PaddingTop"),
	}):Subscribe(function()
		updatePaddingBounds(frame, padding)
	end))
end

const function createShimmerFrame(target: GuiObject): (Frame, UIGradient)
	const frame = Instance.new("Frame")
	frame.Name = "UIShimmer"
	frame.Active = false
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Selectable = false
	frame.Visible = false
	frame.ZIndex = target.ZIndex + 1
	applyDefaultBounds(frame)

	const gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1))
	gradient.Offset = SHIMMER_START_OFFSET
	gradient.Rotation = 15
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 1),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(0.85, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
	frame.Parent = target

	return frame, gradient
end

const function observeShimmer(
	target: GuiObject,
	isEnabled: ShimmerMountable,
	duration: number,
	delayTime: number
): Observable.Observable<never>
	return Observable.new(function(_sub)
		const maid = Maid.new()
		const frame, gradient = createShimmerFrame(target)
		const enabledValue = maid:Add(ValueObject.new(false, t.boolean))
		const tween = TweenService:Create(
			gradient,
			TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, delayTime),
			{ Offset = SHIMMER_END_OFFSET }
		)

		const function stop(): ()
			tween:Cancel()
			gradient.Offset = SHIMMER_START_OFFSET
			frame.Visible = false
		end

		const function updateZIndex(): ()
			frame.ZIndex = target.ZIndex + 1
		end

		maid:Add(frame)
		maid:Add(function()
			tween:Cancel()
		end)
		maid:Add(target:GetPropertyChangedSignal("ZIndex"):Connect(updateZIndex))
		maid:Add(target.ChildAdded:Connect(function(child: Instance)
			if child:IsA("UICorner") then
				syncCorner(maid, target, frame)
			elseif child:IsA("UIPadding") then
				syncPadding(maid, target, frame)
			end
		end))
		maid:Add(target.ChildRemoved:Connect(function(child: Instance)
			if child:IsA("UICorner") then
				syncCorner(maid, target, frame)
			elseif child:IsA("UIPadding") then
				syncPadding(maid, target, frame)
			end
		end))
		maid:Add(enabledValue:Observe():Subscribe(function(enabled: boolean)
			if enabled then
				gradient.Offset = SHIMMER_START_OFFSET
				frame.Visible = true
				tween:Play()
			else
				stop()
			end
		end))

		syncCorner(maid, target, frame)
		syncPadding(maid, target, frame)
		enabledValue:Mount(isEnabled)

		return maid
	end) :: any
end

--[=[
	Returns a Blend functional property that attaches a shimmer to a GuiObject.

	The assigned value may be a boolean, Blend state, `ValueObject<boolean>`,
	`BoolValue`, or `Observable<boolean>`.

	```lua
	Blend.New("Frame")({
		[ShimmerUtils.shimmer({
			Duration = 1,
			DelayTime = 0.25,
		})] = isShimmering,
	})
	```

	@within ShimmerUtils
	@param options ShimmerOptions?
	@return (GuiObject, ShimmerMountable) -> Observable<never>
]=]
function ShimmerUtils.shimmer(options: ShimmerOptions?): (GuiObject, ShimmerMountable) -> Observable.Observable<never>
	assert(t.optional(isOptions)(options), "Bad options")

	const duration = if options then options.Duration or DEFAULT_DURATION else DEFAULT_DURATION
	const delayTime = if options then options.DelayTime or DEFAULT_DELAY_TIME else DEFAULT_DELAY_TIME

	return function(target: GuiObject, isEnabled: ShimmerMountable): Observable.Observable<never>
		assert(t.instanceIsA("GuiObject")(target), "Bad target")
		assert(isBooleanMountable(isEnabled), "Bad isEnabled")

		return observeShimmer(target, isEnabled, duration, delayTime)
	end
end

return ShimmerUtils
