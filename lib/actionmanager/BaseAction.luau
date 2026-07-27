--!strict
--[=[
	BaseAction state for [ActionManager].

	@class BaseAction
]=]

local require = require(script.Parent.loader).load(script)

local ContextActionService = game:GetService("ContextActionService")

local EnabledMixin = require("EnabledMixin")
local Maid = require("Maid")
local Observable = require("Observable")
local Signal = require("Signal")
local ValueObject = require("ValueObject")

local BaseAction = {}
BaseAction.__index = BaseAction
BaseAction.ClassName = "BaseAction"

(EnabledMixin :: any):Add(BaseAction)

export type ActivationMode = "Toggle" | "Hold"

export type ActionData = {
	Name: string,
	Shortcuts: { Enum.KeyCode | Enum.UserInputType }?,
	ActivationMode: ActivationMode?,
	[any]: any,
}

export type BaseAction = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_name: string,
		_contextActionKey: string,
		_activateData: { any }?,
		_actionData: ActionData,

		Activated: Signal.Signal<...any>,
		Deactivated: Signal.Signal<()>,
		IsActivatedValue: ValueObject.ValueObject<boolean>,

		_enabledMaidReference: Maid.Maid,
		_enabledState: ValueObject.ValueObject<boolean>,
		EnabledChanged: Signal.Signal<(boolean, boolean?)>,
		InitEnabledMixin: (self: any, maid: Maid.Maid?) -> (),
		IsEnabled: (self: any) -> boolean,
		Enable: (self: any, doNotAnimate: boolean?) -> (),
		Disable: (self: any, doNotAnimate: boolean?) -> (),
		SetEnabled: (self: any, isEnabled: boolean, doNotAnimate: boolean?) -> (),
		ObserveIsEnabled: (self: any) -> Observable.Observable<boolean>,
	},
	{} :: typeof({ __index = BaseAction })
))

function BaseAction.new(actionData: ActionData): BaseAction
	assert(type(actionData) == "table", "Bad actionData")

	local self: BaseAction = setmetatable({} :: any, BaseAction)

	self._maid = Maid.new()
	self._name = actionData.Name or error("No name")
	self._contextActionKey = string.format("%s_ContextAction", self._name)
	self._activateData = nil

	self.Activated = self._maid:Add(Signal.new() :: Signal.Signal<...any>)
	self.Deactivated = self._maid:Add(Signal.new() :: Signal.Signal<()>)

	self.IsActivatedValue = self._maid:Add(ValueObject.new(false, "boolean"))

	self:InitEnabledMixin()

	self._maid:GiveTask(self.IsActivatedValue.Changed:Connect(function()
		self:_handleIsActiveValueChanged()
	end))

	self._maid:GiveTask(self.EnabledChanged:Connect(function(isEnabled)
		self:_handleEnabledChanged(isEnabled)
	end))

	self:_withActionData(actionData)

	return self
end

function BaseAction._handleEnabledChanged(self: BaseAction, isEnabled: boolean): ()
	if not isEnabled then
		self:Deactivate()
	end

	self:_updateShortcuts()
end

function BaseAction._handleIsActiveValueChanged(self: BaseAction): ()
	if self.IsActivatedValue.Value then
		local actionMaid = Maid.new()
		self._maid._actionMaid = actionMaid

		self.Activated:Fire(actionMaid, unpack(self._activateData or {}))
		self._activateData = nil
	else
		self._maid._actionMaid = nil
		self.Deactivated:Fire()
	end
end

function BaseAction.GetName(self: BaseAction): string
	return self._name
end

function BaseAction.GetActivationMode(self: BaseAction): ActivationMode
	return self._actionData.ActivationMode or "Toggle"
end

function BaseAction._withActionData(self: BaseAction, actionData: ActionData): BaseAction
	self._actionData = actionData

	local activationMode = self:GetActivationMode()
	assert(activationMode == "Toggle" or activationMode == "Hold", "Bad ActivationMode")

	self:_updateShortcuts()

	return self
end

function BaseAction._handleShortcut(self: BaseAction, userInputState: Enum.UserInputState): Enum.ContextActionResult
	local activationMode = self:GetActivationMode()

	if activationMode == "Hold" then
		if userInputState == Enum.UserInputState.Begin then
			self:Activate()
		elseif userInputState == Enum.UserInputState.End or userInputState == Enum.UserInputState.Cancel then
			self:Deactivate()
		end
	else
		if userInputState == Enum.UserInputState.Begin then
			self:ToggleActivate()
		end
	end

	return Enum.ContextActionResult.Pass
end

function BaseAction._updateShortcuts(self: BaseAction): ()
	if not self._actionData then
		return
	end

	ContextActionService:UnbindAction(self._contextActionKey)

	local shortcuts = self._actionData.Shortcuts
	if not shortcuts or #shortcuts == 0 then
		return
	end

	if not self:IsEnabled() then
		return
	end

	ContextActionService:BindAction(
		self._contextActionKey,
		function(_actionName: string, userInputState: Enum.UserInputState, _inputObject: InputObject)
			return self:_handleShortcut(userInputState)
		end,
		false,
		unpack(shortcuts)
	)
end

function BaseAction.GetData(self: BaseAction): ActionData
	return self._actionData
end

function BaseAction.ToggleActivate(self: BaseAction, ...): ()
	if self.IsActivatedValue.Value then
		self:Deactivate()
	else
		self:Activate(...)
	end
end

function BaseAction.IsActive(self: BaseAction): boolean
	return self.IsActivatedValue.Value
end

function BaseAction.Deactivate(self: BaseAction): ()
	self._activateData = nil
	self.IsActivatedValue.Value = false
end

function BaseAction.Activate(self: BaseAction, ...): ()
	if not self:IsEnabled() then
		warn(string.format("[%s.Activate] - Not activating. Disabled!", self:GetName()))
		return
	end

	if self.IsActivatedValue.Value then
		return
	end

	self._activateData = { ... }
	self.IsActivatedValue.Value = true
end

function BaseAction.Destroy(self: BaseAction): ()
	self._maid:DoCleaning()
	setmetatable(self :: any, nil)
end

return BaseAction
