--!strict
--[=[
	Binds one semantic action to its reactive InputKeyMapList and coalesces all
	physical sources into one Begin/End lifecycle.

	@class PlayerInputActionModel
	@client
]=]

const ContextActionService = game:GetService("ContextActionService")
const UserInputService = game:GetService("UserInputService")
const InputKeyMapListUtils = require("@game/ReplicatedStorage/Packages/InputKeyMapListUtils")
const InputModeTypeSelector = require("@game/ReplicatedStorage/Packages/InputModeTypeSelector")
const InputTypeUtils = require("@game/ReplicatedStorage/Packages/InputTypeUtils")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const PlayerInputActionConditionModel = require("../Shared/PlayerInputActionConditionModel")
const PlayerInputServiceTypes = require("../Shared/PlayerInputServiceTypes")
const PlayerInputServiceUtils = require("../Shared/PlayerInputServiceUtils")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

type Action = PlayerInputServiceTypes.Action
type InputState = PlayerInputServiceTypes.InputState
type InputType = PlayerInputServiceTypes.InputType

export type IsAllowedCallback = (action: Action) -> boolean
export type EmitCallback = (action: Action, state: InputState) -> ()

const PlayerInputActionModel = {}
PlayerInputActionModel.ClassName = "PlayerInputActionModel"
PlayerInputActionModel.__index = PlayerInputActionModel

export type PlayerInputActionModel = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_action: Action,
		_actionName: string,
		_conditionModel: PlayerInputActionConditionModel.PlayerInputActionConditionModel,
		_selector: InputModeTypeSelector.InputModeTypeSelector,
		_isAllowed: IsAllowedCallback,
		_emit: EmitCallback,
		_activeInputObjects: { [InputObject]: true },
		_activeVirtualInputs: { [any]: true },
		_activeSourceCount: number,
		_destroyed: boolean,
	},
	{} :: typeof({ __index = PlayerInputActionModel })
))

function PlayerInputActionModel.new(
	serviceBag: ServiceBag.ServiceBag,
	player: Player,
	action: Action,
	isAllowed: IsAllowedCallback,
	emit: EmitCallback
): PlayerInputActionModel
	assert(t.table(serviceBag), "Bad serviceBag")
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(t.table(action), "Bad action")
	assert(t.callback(isAllowed), "Bad isAllowed")
	assert(t.callback(emit), "Bad emit")

	const self = setmetatable({}, PlayerInputActionModel) :: PlayerInputActionModel
	self._maid = Maid.new()
	self._action = action
	self._actionName = `PlayerInputService_{action.ProviderName}_{action.Id}`
	self._conditionModel = self._maid:Add(PlayerInputActionConditionModel.new(player, action))
	self._selector =
		self._maid:Add(InputKeyMapListUtils.getNewInputModeTypeSelector(action.InputKeyMapList, serviceBag))
	self._isAllowed = isAllowed
	self._emit = emit
	self._activeInputObjects = {}
	self._activeVirtualInputs = {}
	self._activeSourceCount = 0
	self._destroyed = false

	self._maid:Add(action.InputKeyMapList:ObserveInputEnumsList():Subscribe(function(inputEnums)
		self:_bindInputEnums(inputEnums :: any)
	end))
	for _, inputKeyMap in action.InputKeyMapList:GetInputKeyMaps() do
		self._maid:Add(inputKeyMap:ObserveInputTypesList():Subscribe(function()
			self:_cancel()
		end))
	end
	self._maid:Add(self._selector.Changed:Connect(function()
		self:_cancel()
	end))

	return self
end

--[=[
	Triggers a headless virtual binding such as Tap, Drag, TouchButton, or a
	slotted touch button. Returns false when the input is not currently bound or
	permitted.

	@within PlayerInputActionModel
	@param inputType InputType
	@param state InputState
	@return boolean
]=]
function PlayerInputActionModel.TriggerInput(
	self: PlayerInputActionModel,
	inputType: InputType,
	state: InputState
): boolean
	assert(t.any(inputType) and InputTypeUtils.isKnownInputType(inputType), "Bad inputType")
	assert(t.string(state) and (state == "Begin" or state == "End" or state == "Cancel"), "Bad state")

	const sourceKey = InputTypeUtils.getUniqueKeyForInputType(inputType)
	if state ~= "Begin" then
		if not self._activeVirtualInputs[sourceKey] then
			return false
		end

		self._activeVirtualInputs[sourceKey] = nil
		self:_decrementSources(state)
		return true
	end

	const activeInputMode = self._selector:GetActiveInputType()
	if
		not activeInputMode or not PlayerInputServiceUtils.isInputTypeBound(self._action, activeInputMode, inputType)
	then
		return false
	end

	if not self:_canBegin() or self._activeVirtualInputs[sourceKey] then
		return false
	end

	self._activeVirtualInputs[sourceKey] = true
	self:_incrementSources()
	return true
end

--[=[
	Returns whether one or more physical or virtual sources currently hold this
	action.

	@within PlayerInputActionModel
	@return boolean
]=]
function PlayerInputActionModel.IsHeld(self: PlayerInputActionModel): boolean
	return self._activeSourceCount > 0
end

--[=[
	Cancels every source currently holding this action.

	@within PlayerInputActionModel
	@return boolean
]=]
function PlayerInputActionModel.ForceRelease(self: PlayerInputActionModel): boolean
	if self._activeSourceCount == 0 then
		return false
	end

	self:_cancel()
	return true
end

--[=[
	Cancels this action if it is active and re-evaluates its current policy.

	@within PlayerInputActionModel
]=]
function PlayerInputActionModel.RefreshPolicy(self: PlayerInputActionModel): ()
	if
		not self._isAllowed(self._action)
		or (not self._action.AllowWhenTextBoxFocused and UserInputService:GetFocusedTextBox())
	then
		self:_cancel()
	end
end

function PlayerInputActionModel._bindInputEnums(
	self: PlayerInputActionModel,
	inputEnums: { Enum.KeyCode | Enum.UserInputType }
): ()
	self:_cancel()
	self._maid._contextActionBinding = nil

	if #inputEnums == 0 then
		return
	end

	ContextActionService:BindActionAtPriority(
		self._actionName,
		function(
			_actionName: string,
			userInputState: Enum.UserInputState,
			inputObject: InputObject
		): Enum.ContextActionResult
			return self:_handleContextAction(userInputState, inputObject)
		end,
		false,
		self._action.ContextActionPriority,
		unpack(inputEnums)
	)

	self._maid._contextActionBinding = function()
		ContextActionService:UnbindAction(self._actionName)
	end
end

function PlayerInputActionModel._handleContextAction(
	self: PlayerInputActionModel,
	userInputState: Enum.UserInputState,
	inputObject: InputObject
): Enum.ContextActionResult
	if userInputState == Enum.UserInputState.Begin then
		if not self._conditionModel:AreConditionsMet() then
			return if self._action.ConsumeInputWhenConditionFails
				then Enum.ContextActionResult.Sink
				else Enum.ContextActionResult.Pass
		end
		if
			not self:_canBegin()
			or self._activeInputObjects[inputObject]
			or not PlayerInputServiceUtils.isInputObjectBound(self._action, inputObject, function(keyCode)
				return UserInputService:IsKeyDown(keyCode)
			end)
		then
			return Enum.ContextActionResult.Pass
		end

		self._activeInputObjects[inputObject] = true
		self:_incrementSources()
	elseif userInputState == Enum.UserInputState.End or userInputState == Enum.UserInputState.Cancel then
		if not self._activeInputObjects[inputObject] then
			return Enum.ContextActionResult.Pass
		end

		self._activeInputObjects[inputObject] = nil
		self:_decrementSources(if userInputState == Enum.UserInputState.Cancel then "Cancel" else "End")
	else
		return Enum.ContextActionResult.Pass
	end

	return if self._action.ConsumeInput then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
end

function PlayerInputActionModel._canBegin(self: PlayerInputActionModel): boolean
	if not self._conditionModel:AreConditionsMet() then
		return false
	end
	if not self._isAllowed(self._action) then
		return false
	end
	if not self._action.AllowWhenTextBoxFocused and UserInputService:GetFocusedTextBox() then
		return false
	end

	return true
end

function PlayerInputActionModel._incrementSources(self: PlayerInputActionModel): ()
	self._activeSourceCount += 1
	if self._activeSourceCount == 1 then
		self._emit(self._action, "Begin")
	end
end

function PlayerInputActionModel._decrementSources(self: PlayerInputActionModel, state: "End" | "Cancel"): ()
	self._activeSourceCount = math.max(0, self._activeSourceCount - 1)
	if self._activeSourceCount == 0 then
		self._emit(self._action, state)
	end
end

function PlayerInputActionModel._cancel(self: PlayerInputActionModel): ()
	if self._activeSourceCount == 0 then
		return
	end

	table.clear(self._activeInputObjects)
	table.clear(self._activeVirtualInputs)
	self._activeSourceCount = 0
	self._emit(self._action, "Cancel")
end

function PlayerInputActionModel.Destroy(self: PlayerInputActionModel): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self:_cancel()
	self._maid:DoCleaning()
end

return PlayerInputActionModel
