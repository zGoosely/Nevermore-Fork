--!strict
--[=[
	Centralizes local input processing and exposes reusable InputMode state.

	@client
	@class InputModeServiceClient
]=]

const GuiService = game:GetService("GuiService")
const UserInputService = game:GetService("UserInputService")

const require = require("../../Loader").load()

const InputMode = require("InputMode")
const InputModeProcessor = require("InputModeProcessor")
const InputModeType = require("InputModeType")
const InputModeTypes = require("InputModeTypes")
const Maid = require("Maid")
const ServiceBag = require("ServiceBag")

const THUMBSTICK_DEADZONE = 0.14

const InputModeServiceClient = {}
InputModeServiceClient.ServiceName = "InputModeServiceClient"

export type InputModeServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_inputModes: { [InputModeType.InputModeType]: InputMode.InputMode },
		_inputModeProcessor: InputModeProcessor.InputModeProcessor,
		_lastMousePosition: Vector3?,
	},
	{} :: typeof({ __index = InputModeServiceClient })
))

function InputModeServiceClient.Init(self: InputModeServiceClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._inputModes = {}
	self._lastMousePosition = nil
	self._inputModeProcessor = self._maid:Add(InputModeProcessor.new())

	-- Register broad modes before their specific subsets so selectors have stable
	-- tie-breaking behavior.
	self:GetInputMode(InputModeTypes.KeyboardAndMouse)
	self:GetInputMode(InputModeTypes.Gamepads)
	self:GetInputMode(InputModeTypes.Keyboard)
	self:GetInputMode(InputModeTypes.Touch)
	self:GetInputMode(InputModeTypes.Mouse)
	self:GetInputMode(InputModeTypes.ArrowKeys)
	self:GetInputMode(InputModeTypes.Keypad)
	self:GetInputMode(InputModeTypes.WASD)
	self:GetInputMode(InputModeTypes.DPad)
	self:_triggerEnabled()
end

function InputModeServiceClient.Start(self: InputModeServiceClient)
	self:_bindProcessor()
end

--[=[
	Returns the shared runtime state for an input mode definition, creating it when
	needed.

	@within InputModeServiceClient
	@param inputModeType InputModeType
	@return InputMode
]=]
function InputModeServiceClient.GetInputMode(
	self: InputModeServiceClient,
	inputModeType: InputModeType.InputModeType
): InputMode.InputMode
	assert(InputModeType.isInputModeType(inputModeType), "Bad inputModeType")

	const existing = self._inputModes[inputModeType]
	if existing then
		return existing
	end

	const inputMode = InputMode.new(inputModeType)
	self._inputModeProcessor:AddInputMode(inputMode)
	self._maid:Add(inputMode)
	self._inputModes[inputModeType] = inputMode
	return inputMode
end

function InputModeServiceClient._triggerEnabled(self: InputModeServiceClient)
	if UserInputService.MouseEnabled then
		self:GetInputMode(InputModeTypes.Mouse):Enable()
	end
	if UserInputService.TouchEnabled then
		self:GetInputMode(InputModeTypes.Touch):Enable()
	end
	if UserInputService.KeyboardEnabled then
		self:GetInputMode(InputModeTypes.Keyboard):Enable()
	end
	if UserInputService.KeyboardEnabled and UserInputService.MouseEnabled then
		self:GetInputMode(InputModeTypes.KeyboardAndMouse):Enable()
	end
	if
		UserInputService.GamepadEnabled
		or #UserInputService:GetConnectedGamepads() > 0
		or GuiService:IsTenFootInterface()
	then
		self:GetInputMode(InputModeTypes.Gamepads):Enable()
	end
end

function InputModeServiceClient._bindProcessor(self: InputModeServiceClient)
	self._maid:Add(UserInputService.InputBegan:Connect(function(inputObject: InputObject)
		self._inputModeProcessor:Evaluate(inputObject)
	end))
	self._maid:Add(UserInputService.InputEnded:Connect(function(inputObject: InputObject)
		self._inputModeProcessor:Evaluate(inputObject)
	end))
	self._maid:Add(UserInputService.InputChanged:Connect(function(inputObject: InputObject)
		if inputObject.KeyCode == Enum.KeyCode.Thumbstick1 or inputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
			if inputObject.Position.Magnitude > THUMBSTICK_DEADZONE then
				self._inputModeProcessor:Evaluate(inputObject)
				self:GetInputMode(InputModeTypes.Thumbsticks):Enable()
			end
		elseif inputObject.UserInputType == Enum.UserInputType.MouseMovement then
			if self:_shouldProcessMouseMovement(inputObject) then
				self._inputModeProcessor:Evaluate(inputObject)
			end
		else
			self._inputModeProcessor:Evaluate(inputObject)
		end
	end))
	self._maid:Add(UserInputService.GamepadConnected:Connect(function()
		self:GetInputMode(InputModeTypes.Gamepads):Enable()
	end))
	self._maid:Add(UserInputService.GamepadDisconnected:Connect(function()
		self:_triggerEnabled()
	end))
end

function InputModeServiceClient._shouldProcessMouseMovement(
	self: InputModeServiceClient,
	inputObject: InputObject
): boolean
	const position = inputObject.Position
	const lastMousePosition = self._lastMousePosition
	self._lastMousePosition = position

	return inputObject.Delta.Magnitude > 0
		or lastMousePosition == nil
		or ((lastMousePosition :: Vector3) - position).Magnitude > 0
end

function InputModeServiceClient.Destroy(self: InputModeServiceClient)
	self._maid:DoCleaning()
	table.clear(self)
	setmetatable(self, nil)
end

return InputModeServiceClient
