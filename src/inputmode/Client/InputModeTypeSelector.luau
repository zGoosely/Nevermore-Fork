--!strict
--[=[
	Selects the most recently used mode from an ordered set of InputModeTypes.

	@class InputModeTypeSelector
]=]

const require = require("../../Loader").load()

const Brio = require("Brio")
const InputModeServiceClient = require("InputModeServiceClient")
const InputModeType = require("InputModeType")
const InputModeTypes = require("InputModeTypes")
const Maid = require("Maid")
const Observable = require("Observable")
const Rx = require("Rx")
const ServiceBag = require("ServiceBag")
const Signal = require("Signal")
const ValueObject = require("ValueObject")

const InputModeTypeSelector = {}
InputModeTypeSelector.ClassName = "InputModeTypeSelector"
InputModeTypeSelector.DEFAULT_MODE_TYPES = table.freeze({
	InputModeTypes.Gamepads,
	InputModeTypes.Keyboard,
	InputModeTypes.Touch,
}) :: { InputModeType.InputModeType }

export type InputModeTypeSelector = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_inputModeTypeList: { InputModeType.InputModeType },
		_activeModeType: ValueObject.ValueObject<InputModeType.InputModeType?>,
		_serviceBag: ServiceBag.ServiceBag,
		_inputModeServiceClient: InputModeServiceClient.InputModeServiceClient,
		Value: InputModeType.InputModeType?,
		Changed: Signal.Signal<any>,
	},
	{} :: typeof({ __index = InputModeTypeSelector })
))

--[=[
	Creates a selector for the supplied modes. The default modes are Gamepads,
	Keyboard, and Touch.

	@within InputModeTypeSelector
	@param serviceBag ServiceBag
	@param inputModeTypes { InputModeType }?
	@return InputModeTypeSelector
]=]
function InputModeTypeSelector.new(
	serviceBag: ServiceBag.ServiceBag,
	inputModeTypes: { InputModeType.InputModeType }?
): InputModeTypeSelector
	assert(ServiceBag.isServiceBag(serviceBag), "Bad serviceBag")

	const self: InputModeTypeSelector = setmetatable({} :: any, InputModeTypeSelector)
	self._serviceBag = serviceBag
	self._inputModeServiceClient = serviceBag:GetService(InputModeServiceClient)
	self._maid = Maid.new()
	self._inputModeTypeList = {}
	self._activeModeType = self._maid:Add(ValueObject.new(nil))
	self.Changed = self._activeModeType.Changed

	for _, inputModeType in inputModeTypes or InputModeTypeSelector.DEFAULT_MODE_TYPES do
		self:AddInputModeType(inputModeType)
	end

	return self
end

--[=[
	Creates a selector whose available mode definitions follow an observable of
	Brios.

	@within InputModeTypeSelector
	@param serviceBag ServiceBag
	@param observeInputModesBrio Observable<Brio<InputModeType>>
	@return InputModeTypeSelector
]=]
function InputModeTypeSelector.fromObservableBrio(
	serviceBag: ServiceBag.ServiceBag,
	observeInputModesBrio: Observable.Observable<Brio.Brio<InputModeType.InputModeType>>
): InputModeTypeSelector
	const selector = InputModeTypeSelector.new(serviceBag, {})
	selector._maid:Add(observeInputModesBrio:Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		const inputModeType = brio:GetValue()
		const maid = brio:ToMaid()
		selector:AddInputModeType(inputModeType)
		maid:Add(function()
			if selector.Destroy then
				selector:RemoveInputModeType(inputModeType)
			end
		end)
	end))
	return selector
end

--[=[
	Returns the most recently used available mode.

	@within InputModeTypeSelector
	@return InputModeType?
]=]
function InputModeTypeSelector.GetActiveInputType(self: InputModeTypeSelector): InputModeType.InputModeType?
	return (rawget(self :: any, "_activeModeType") :: ValueObject.ValueObject<InputModeType.InputModeType?>).Value
end

--[=[
	Observes the most recently used available mode.

	@within InputModeTypeSelector
	@return Observable<InputModeType?>
]=]
function InputModeTypeSelector.ObserveActiveInputType(
	self: InputModeTypeSelector
): Observable.Observable<InputModeType.InputModeType?>
	return (rawget(self :: any, "_activeModeType") :: ValueObject.ValueObject<InputModeType.InputModeType?>):Observe()
end

--[=[
	Returns whether a mode is currently selected.

	@within InputModeTypeSelector
	@param inputModeType InputModeType
	@return boolean
]=]
function InputModeTypeSelector.IsActive(
	self: InputModeTypeSelector,
	inputModeType: InputModeType.InputModeType
): boolean
	assert(InputModeType.isInputModeType(inputModeType), "Bad inputModeType")
	return self:GetActiveInputType() == inputModeType
end

--[=[
	Observes whether a mode is currently selected.

	@within InputModeTypeSelector
	@param inputModeType InputModeType
	@return Observable<boolean>
]=]
function InputModeTypeSelector.ObserveIsActive(
	self: InputModeTypeSelector,
	inputModeType: InputModeType.InputModeType
): Observable.Observable<boolean>
	assert(InputModeType.isInputModeType(inputModeType), "Bad inputModeType")
	return self:ObserveActiveInputType():Pipe({
		Rx.map(function(activeInputModeType)
			return activeInputModeType == inputModeType
		end) :: any,
		Rx.distinct() :: any,
	}) :: any
end

--[=[
	Runs a callback immediately and whenever the selected mode changes. The mode
	Maid is cleaned before the callback is invoked for a new mode.

	@within InputModeTypeSelector
	@param updateBindFunction (InputModeType, Maid) -> ()
	@return InputModeTypeSelector
]=]
function InputModeTypeSelector.Bind(
	self: InputModeTypeSelector,
	updateBindFunction: (InputModeType.InputModeType, Maid.Maid) -> ()
): InputModeTypeSelector
	assert(type(updateBindFunction) == "function", "Bad updateBindFunction")

	const maid = Maid.new()
	self._maid[updateBindFunction] = maid

	local function onChange(newMode: InputModeType.InputModeType?)
		maid._modeMaid = nil
		if newMode then
			const modeMaid = Maid.new()
			maid._modeMaid = modeMaid
			updateBindFunction(newMode, modeMaid)
		end
	end

	maid:Add(self._activeModeType.Changed:Connect(onChange))
	onChange(self._activeModeType.Value)
	return self
end

--[=[
	Removes an available mode from the selector.

	@within InputModeTypeSelector
	@param inputModeType InputModeType
]=]
function InputModeTypeSelector.RemoveInputModeType(
	self: InputModeTypeSelector,
	inputModeType: InputModeType.InputModeType
)
	assert(InputModeType.isInputModeType(inputModeType), "Bad inputModeType")
	if not self._maid[inputModeType] then
		return
	end

	const index = table.find(self._inputModeTypeList, inputModeType)
	if index then
		table.remove(self._inputModeTypeList, index)
	end
	self._maid[inputModeType] = nil

	if self._activeModeType.Value == inputModeType then
		self:_pickNewInputMode()
	end
end

--[=[
	Adds an available mode to the selector.

	@within InputModeTypeSelector
	@param inputModeType InputModeType
]=]
function InputModeTypeSelector.AddInputModeType(self: InputModeTypeSelector, inputModeType: InputModeType.InputModeType)
	assert(InputModeType.isInputModeType(inputModeType), "Bad inputModeType")
	if self._maid[inputModeType] then
		return
	end

	table.insert(self._inputModeTypeList, inputModeType)
	const inputMode = self._inputModeServiceClient:GetInputMode(inputModeType)
	self._maid[inputModeType] = inputMode.Enabled:Connect(function()
		self._activeModeType.Value = inputModeType
	end)

	const activeMode = self._activeModeType.Value
	if
		activeMode == nil
		or inputMode:GetLastEnabledTime()
			> self._inputModeServiceClient:GetInputMode(activeMode):GetLastEnabledTime()
	then
		self._activeModeType.Value = inputModeType
	end
end

--[=[
	The currently selected InputModeType.

	@prop Value InputModeType?
	@within InputModeTypeSelector
]=]
function InputModeTypeSelector.__index(self: InputModeTypeSelector, index: string): any
	if index == "Value" then
		return (rawget(self :: any, "_activeModeType") :: ValueObject.ValueObject<InputModeType.InputModeType?>).Value
	end

	const classValue = InputModeTypeSelector[index]
	if classValue ~= nil then
		return classValue
	end

	const value = rawget(self :: any, index)
	if value ~= nil then
		return value
	end

	error(`Bad InputModeTypeSelector index {index}`)
end

function InputModeTypeSelector._pickNewInputMode(self: InputModeTypeSelector)
	local bestEnabledTime = -math.huge
	local bestModeType = nil
	for _, inputModeType in self._inputModeTypeList do
		const enabledTime = self._inputModeServiceClient:GetInputMode(inputModeType):GetLastEnabledTime()
		if enabledTime >= bestEnabledTime then
			bestEnabledTime = enabledTime
			bestModeType = inputModeType
		end
	end
	self._activeModeType.Value = bestModeType
end

function InputModeTypeSelector.Destroy(self: InputModeTypeSelector)
	self._maid:DoCleaning()
	table.clear(self)
	setmetatable(self, nil)
end

return InputModeTypeSelector
