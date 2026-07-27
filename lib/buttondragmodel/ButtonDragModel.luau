--!strict
--[=[
	Tracks mouse and touch dragging over a GuiButton and exposes normalized button
	position, accumulated drag delta, and pressed-state observables.

	@class ButtonDragModel
	@client
]=]

const UserInputService = game:GetService("UserInputService")

const require = require("../Loader").load()

const BaseObject = require("BaseObject")
const Brio = require("Brio")
const InputObjectUtils = require("InputObjectUtils")
const Maid = require("Maid")
const Observable = require("Observable")
const Signal = require("Signal")
const ValueObject = require("ValueObject")

const ButtonDragModel = setmetatable({}, BaseObject)
ButtonDragModel.ClassName = "ButtonDragModel"
ButtonDragModel.__index = ButtonDragModel

export type ButtonDragModel =
	typeof(setmetatable(
		{} :: {
			_dragPosition: ValueObject.ValueObject<Vector2?>,
			_dragDelta: ValueObject.ValueObject<Vector2?>,
			_isMouseDown: ValueObject.ValueObject<boolean>,
			_button: ValueObject.ValueObject<GuiButton?>,
			_isPressed: ValueObject.ValueObject<boolean>,
			_clampWithinButton: ValueObject.ValueObject<boolean>,
			_activePositions: { [InputObject | string]: Vector2? },

			DragPositionChanged: Signal.Signal<(Vector2?, Vector2?, ...any)>,
			IsDraggingChanged: Signal.Signal<boolean>,
		},
		{} :: typeof({ __index = ButtonDragModel })
	))
	& BaseObject.BaseObject

--[=[
	Creates a drag model, optionally bound to a button immediately.

	@within ButtonDragModel
	@param initialButton GuiButton?
	@return ButtonDragModel
]=]
function ButtonDragModel.new(initialButton: GuiButton?): ButtonDragModel
	const self = setmetatable(BaseObject.new() :: any, ButtonDragModel) :: ButtonDragModel

	self._isMouseDown = self._maid:Add(ValueObject.new(false, "boolean"))
	self._dragPosition = self._maid:Add(ValueObject.new(nil))
	self._dragDelta = self._maid:Add(ValueObject.new(nil))
	self._button = self._maid:Add(ValueObject.new(nil))
	self._isPressed = self._maid:Add(ValueObject.new(false, "boolean"))
	self._clampWithinButton = self._maid:Add(ValueObject.new(false, "boolean"))
	self._activePositions = {}

	self._maid:Add(self._dragPosition.Changed:Connect(function()
		self._isPressed.Value = self._dragPosition.Value ~= nil
	end))

	self.DragPositionChanged = self._dragPosition.Changed
	self.IsDraggingChanged = self._isPressed.Changed :: any

	if initialButton then
		self:SetButton(initialButton)
	end

	self._maid:Add(self._button
		:ObserveBrio(function(button: GuiButton?)
			return button ~= nil
		end)
		:Subscribe(function(brio)
			if brio:IsDead() then
				return
			end

			const maid, button = brio:ToMaidAndValue()
			self:_setupDragging(maid, button :: GuiButton)
		end))

	return self
end

--[=[
	Returns whether a mouse or touch input is pressing the button.

	@within ButtonDragModel
	@return boolean
]=]
function ButtonDragModel.IsPressed(self: ButtonDragModel): boolean
	return self._isPressed.Value
end

--[=[
	Observes whether the button is pressed.

	@within ButtonDragModel
	@return Observable<boolean>
]=]
function ButtonDragModel.ObserveIsPressed(self: ButtonDragModel): Observable.Observable<boolean>
	return self._isPressed:Observe()
end

--[=[
	Observes each pressed lifetime as a Brio.

	@within ButtonDragModel
	@return Observable<Brio<boolean>>
]=]
function ButtonDragModel.ObserveIsPressedBrio(self: ButtonDragModel): Observable.Observable<Brio.Brio<boolean>>
	return self._isPressed:ObserveBrio(function(value)
		return value :: any
	end) :: any
end

--[=[
	Observes the accumulated pointer movement for the active drag.

	@within ButtonDragModel
	@return Observable<Vector2?>
]=]
function ButtonDragModel.ObserveDragDelta(self: ButtonDragModel): Observable.Observable<Vector2?>
	return self._dragDelta:Observe()
end

--[=[
	Returns accumulated pointer movement for the active drag.

	@within ButtonDragModel
	@return Vector2?
]=]
function ButtonDragModel.GetDragDelta(self: ButtonDragModel): Vector2?
	return self._dragDelta.Value
end

--[=[
	Returns the normalized pointer position relative to the button.

	@within ButtonDragModel
	@return Vector2?
]=]
function ButtonDragModel.GetDragPosition(self: ButtonDragModel): Vector2?
	return self._dragPosition.Value
end

--[=[
	Observes the normalized pointer position relative to the button.

	@within ButtonDragModel
	@return Observable<Vector2?>
]=]
function ButtonDragModel.ObserveDragPosition(self: ButtonDragModel): Observable.Observable<Vector2?>
	return self._dragPosition:Observe()
end

--[=[
	Controls whether normalized positions are clamped to the zero-to-one range.

	@within ButtonDragModel
	@param clampWithinButton boolean
]=]
function ButtonDragModel.SetClampWithinButton(self: ButtonDragModel, clampWithinButton: boolean): ()
	assert(type(clampWithinButton) == "boolean", "Bad clampWithinButton")
	self._clampWithinButton.Value = clampWithinButton
end

--[=[
	Binds the model to a button. Passing nil unbinds the current button.

	@within ButtonDragModel
	@param button GuiButton?
	@return () -> ()
]=]
function ButtonDragModel.SetButton(self: ButtonDragModel, button: GuiButton?): () -> ()
	assert(button == nil or (typeof(button) == "Instance" and button:IsA("GuiButton")), "Bad button")
	self._button.Value = button

	return function()
		if self._button.Value == button then
			self._button.Value = nil
		end
	end
end

function ButtonDragModel._setupDragging(self: ButtonDragModel, maid: Maid.Maid, button: GuiButton): ()
	maid:Add(self._clampWithinButton.Changed:Connect(function()
		self:_updateCurrentPosition()
	end))

	maid:Add(button.InputBegan:Connect(function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
			self._activePositions.mouse = self:_toButtonSpace(button, inputObject.Position)
			self._isMouseDown.Value = true
			self:_updateCurrentPosition()
		elseif inputObject.UserInputType == Enum.UserInputType.Touch then
			self:_trackTouch(maid, button, inputObject)
		end
	end))

	maid:Add(button.InputEnded:Connect(function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
			self._activePositions.mouse = nil
			self._isMouseDown.Value = false
		elseif inputObject.UserInputType == Enum.UserInputType.Touch then
			self:_stopTouchTrack(maid, inputObject)
		end
	end))

	maid:Add(UserInputService.InputEnded:Connect(function(inputObject)
		if inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
			self._activePositions.mouse = nil
			self._isMouseDown.Value = false
			self:_updateCurrentPosition()
		end
	end))

	maid:Add(function()
		self._activePositions.mouse = nil
		self._isMouseDown.Value = false
		self:_updateCurrentPosition()
	end)

	maid:Add(self._isMouseDown.Changed:Connect(function()
		if self._isMouseDown.Value then
			maid._mouse = self:_updateMouseTracking(button)
		else
			maid._mouse = nil
		end
	end))
end

function ButtonDragModel._updateMouseTracking(self: ButtonDragModel, button: GuiButton): Maid.Maid
	const maid = Maid.new()
	local lastMousePosition: Vector3? = nil

	local function setMousePosition(inputObject: InputObject)
		const previous = lastMousePosition
		const current = inputObject.Position
		lastMousePosition = current

		if previous then
			self:_incrementDragDelta(current - previous)
		end

		self._activePositions.mouse = self:_toButtonSpace(button, current)
		self:_updateCurrentPosition()
	end

	maid:Add(UserInputService.InputChanged:Connect(function(inputObject)
		if not InputObjectUtils.isMouseUserInputType(inputObject.UserInputType) then
			return
		end

		const screenGui = button:FindFirstAncestorWhichIsA("ScreenGui")
		if
			not screenGui
			or not (screenGui:FindFirstAncestorWhichIsA("PlayerGui") or screenGui:FindFirstAncestorWhichIsA("CoreGui"))
		then
			self._activePositions.mouse = nil
			self:_updateCurrentPosition()
			return
		end

		setMousePosition(inputObject)
	end))

	maid:Add(button.InputChanged:Connect(function(inputObject)
		if InputObjectUtils.isMouseUserInputType(inputObject.UserInputType) then
			setMousePosition(inputObject)
		end
	end))

	maid:Add(function()
		self._activePositions.mouse = nil
		self:_updateCurrentPosition()
	end)

	return maid
end

function ButtonDragModel._trackTouch(
	self: ButtonDragModel,
	buttonMaid: Maid.Maid,
	button: GuiButton,
	inputObject: InputObject
): ()
	buttonMaid[inputObject] = nil
	if inputObject.UserInputState == Enum.UserInputState.End then
		return
	end

	const maid = Maid.new()
	self._activePositions[inputObject] = self:_toButtonSpace(button, inputObject.Position)
	self:_incrementDragDelta(inputObject.Delta)

	maid:Add(inputObject:GetPropertyChangedSignal("Delta"):Connect(function()
		self:_incrementDragDelta(inputObject.Delta)
	end))
	maid:Add(inputObject:GetPropertyChangedSignal("Position"):Connect(function()
		self._activePositions[inputObject] = self:_toButtonSpace(button, inputObject.Position)
		self:_updateCurrentPosition()
	end))
	maid:Add(inputObject:GetPropertyChangedSignal("UserInputState"):Connect(function()
		if inputObject.UserInputState == Enum.UserInputState.End then
			buttonMaid[inputObject] = nil
		end
	end))
	maid:Add(function()
		self._activePositions[inputObject] = nil
		self:_updateCurrentPosition()
	end)

	buttonMaid[inputObject] = maid
	self:_updateCurrentPosition()
end

function ButtonDragModel._stopTouchTrack(_self: ButtonDragModel, buttonMaid: Maid.Maid, inputObject: InputObject): ()
	buttonMaid[inputObject] = nil
end

function ButtonDragModel._toButtonSpace(_self: ButtonDragModel, button: GuiButton, position: Vector3): Vector2
	const size = button.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return Vector2.zero
	end
	return (Vector2.new(position.X, position.Y) - button.AbsolutePosition) / size
end

function ButtonDragModel._updateCurrentPosition(self: ButtonDragModel): ()
	local current = Vector2.zero
	local count = 0
	for _, item in self._activePositions do
		if item then
			current += item
			count += 1
		end
	end
	if count == 0 then
		self._dragPosition.Value = nil
		self._dragDelta.Value = nil
		return
	end

	current /= count
	local x = current.X
	local y = current.Y
	if self._clampWithinButton.Value then
		x = math.clamp(x, 0, 1)
		y = math.clamp(y, 0, 1)
	end

	self._dragPosition.Value = Vector2.new(x, y)
	if not self._dragDelta.Value then
		self._dragDelta.Value = Vector2.zero
	end
end

function ButtonDragModel._incrementDragDelta(self: ButtonDragModel, delta: Vector3): ()
	const current = self._dragDelta.Value or Vector2.zero
	self._dragDelta.Value = current + Vector2.new(delta.X, delta.Y)
end

return ButtonDragModel
