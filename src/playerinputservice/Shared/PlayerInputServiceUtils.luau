--!strict
--[=[
	Validates PlayerInputService definitions and converts keymap values to compact,
	network-safe binding records.

	@util PlayerInputServiceUtils
]=]

const CollectionService = game:GetService("CollectionService")

const require = require("../../Loader").load()

const AdorneeConditionUtils = require("AdorneeConditionUtils")
const EnumUtils = require("EnumUtils")
const InputChordUtils = require("InputChordUtils")
const InputKeyMapList = require("InputKeyMapList")
const InputModeTypes = require("InputModeTypes")
const InputTypeUtils = require("InputTypeUtils")
const PlayerInputModeTypes = require("PlayerInputModeTypes")
const PlayerInputServiceConstants = require("PlayerInputServiceConstants")
const PlayerInputServiceTypes = require("PlayerInputServiceTypes")
const SlottedTouchButtonUtils = require("SlottedTouchButtonUtils")
const TableUtils = require("TableUtils")
const t = require("t")

type Action = PlayerInputServiceTypes.Action
type ActionCooldownType = PlayerInputServiceTypes.ActionCooldownType
type ActionCooldownValue = PlayerInputServiceTypes.ActionCooldownValue
type ActionConfig = PlayerInputServiceTypes.ActionConfig
type BindingOverride = PlayerInputServiceTypes.BindingOverride
type InputMode = PlayerInputServiceTypes.InputMode
type InputType = PlayerInputServiceTypes.InputType
type InputState = PlayerInputServiceTypes.InputState
type NetworkInputState = PlayerInputServiceTypes.NetworkInputState
type SerializedInputType = PlayerInputServiceTypes.SerializedInputType
type ActionIdSet = { [number]: true }

const isNetworkPolicyConfig = t.strictInterface({
	States = t.array(t.string),
	Capacity = t.numberPositive,
	RefillRate = t.numberPositive,
})

const isDefaultCooldownValue = t.strictInterface({
	Duration = t.number,
})

const isBurstCooldownValue = t.strictInterface({
	Duration = t.number,
	Count = t.integer,
	Window = t.number,
	PenaltyDuration = t.number,
})

const isKeyCode = t.enum(Enum.KeyCode)
const isUserInputType = t.enum(Enum.UserInputType)

const isActionConfig = t.strictInterface({
	Id = t.number,
	Name = t.string,
	InputKeyMapList = t.table,
	AllowedContexts = t.optional(t.array(t.string)),
	AllowedPlayerInputModes = t.optional(t.array(t.string)),
	ConsumeInput = t.optional(t.boolean),
	ContextActionPriority = t.optional(t.number),
	AllowWhenTextBoxFocused = t.optional(t.boolean),
	AdorneeConditionContext = t.optional(t.callback),
	ConsumeInputWhenConditionFails = t.optional(t.boolean),
	Network = t.optional(isNetworkPolicyConfig),
	CooldownType = t.optional(t.string),
	CooldownValue = t.optional(t.table),
	CooldownOnCancel = t.optional(t.boolean),
})

const isSerializedInputType = t.strictInterface({
	Kind = t.number,
	Name = t.string,
	Modifiers = t.optional(t.array(t.string)),
})

const isBindingOverride = t.strictInterface({
	ActionId = t.number,
	InputModeName = t.string,
	InputTypes = t.array(isSerializedInputType),
	Clear = t.boolean,
})

const isContextName = function(value: any): boolean
	return t.string(value) and value ~= ""
end

const isInitialState = t.strictInterface({
	AllowedActionIds = t.array(t.number),
	BindingOverrides = t.array(isBindingOverride),
	ContextName = isContextName,
	PolicyRevision = t.number,
	BindingRevision = t.number,
})

const PlayerInputServiceUtils = {}

local function createStringSet(values: { string }, argumentName: string): { [string]: true }
	const result: { [string]: true } = {}

	for _, value in values do
		assert(t.string(value) and value ~= "", `Bad {argumentName}`)
		result[value] = true
	end

	return table.freeze(result)
end

local function inferPlayerInputModes(inputKeyMapList: InputKeyMapList.InputKeyMapList): {
	[PlayerInputModeTypes.PlayerInputModeType]: true,
}
	const result: { [PlayerInputModeTypes.PlayerInputModeType]: true } = {}

	for _, inputKeyMap in inputKeyMapList:GetInputKeyMaps() do
		const inputModeType = inputKeyMap:GetInputModeType()

		if inputModeType == InputModeTypes.Gamepads then
			result[PlayerInputModeTypes.GAMEPAD] = true
		elseif inputModeType == InputModeTypes.KeyboardAndMouse then
			result[PlayerInputModeTypes.KEYBOARD] = true
		elseif inputModeType == InputModeTypes.Touch then
			result[PlayerInputModeTypes.TOUCH] = true
		end
	end

	return result
end

local function isKnownPlayerInputMode(inputMode: string): boolean
	return inputMode == PlayerInputModeTypes.GAMEPAD
		or inputMode == PlayerInputModeTypes.KEYBOARD
		or inputMode == PlayerInputModeTypes.TOUCH
end

local function isPositiveFiniteNumber(value: any): boolean
	return t.number(value) and value > 0 and value < math.huge
end

local function createCooldownValue(
	cooldownType: ActionCooldownType?,
	cooldownValue: ActionCooldownValue?
): ActionCooldownValue?
	if cooldownType == nil and cooldownValue == nil then
		return nil
	end

	assert(cooldownType ~= nil and cooldownValue ~= nil, "CooldownType and CooldownValue must be provided together")
	assert(cooldownType == "Default" or cooldownType == "Burst", "Bad config.CooldownType")

	if cooldownType == "Default" then
		assert(isDefaultCooldownValue(cooldownValue), "Bad config.CooldownValue")
	else
		assert(
			isBurstCooldownValue(cooldownValue)
				and cooldownValue.Count >= 2
				and isPositiveFiniteNumber(cooldownValue.Window)
				and isPositiveFiniteNumber(cooldownValue.PenaltyDuration)
				and cooldownValue.PenaltyDuration > cooldownValue.Duration,
			"Bad config.CooldownValue"
		)
	end
	assert(isPositiveFiniteNumber(cooldownValue.Duration), "Bad config.CooldownValue.Duration")

	return table.freeze(table.clone(cooldownValue))
end

--[=[
	Returns the globally unique lookup key for an action.

	@within PlayerInputServiceUtils
	@param providerName string
	@param actionName string
	@return string
]=]
function PlayerInputServiceUtils.getActionKey(providerName: string, actionName: string): string
	assert(t.string(providerName) and providerName ~= "", "Bad providerName")
	assert(t.string(actionName) and actionName ~= "", "Bad actionName")
	return `{providerName}.{actionName}`
end

--[=[
	Constructs and freezes a validated action definition.

	@within PlayerInputServiceUtils
	@param providerName string
	@param config ActionConfig
	@return Action
]=]
function PlayerInputServiceUtils.createAction(providerName: string, config: ActionConfig): Action
	assert(t.string(providerName) and providerName ~= "", "Bad providerName")
	assert(isActionConfig(config), "Bad config")
	assert(
		config.Id % 1 == 0
			and config.Id >= PlayerInputServiceConstants.MIN_ACTION_ID
			and config.Id <= PlayerInputServiceConstants.MAX_ACTION_ID,
		"Bad config.Id"
	)
	assert(config.Name ~= "", "Bad config.Name")
	assert(
		config.ContextActionPriority == nil
			or (
				config.ContextActionPriority > -math.huge
				and config.ContextActionPriority < math.huge
				and config.ContextActionPriority == config.ContextActionPriority
			),
		"Bad config.ContextActionPriority"
	)
	assert(
		t.table(config.InputKeyMapList) and InputKeyMapList.isInputKeyMapList(config.InputKeyMapList),
		"Bad config.InputKeyMapList"
	)
	assert(
		not config.ConsumeInputWhenConditionFails or config.AdorneeConditionContext ~= nil,
		"config.ConsumeInputWhenConditionFails requires config.AdorneeConditionContext"
	)

	const cooldownValue = createCooldownValue(config.CooldownType, config.CooldownValue)
	assert(not config.CooldownOnCancel or cooldownValue ~= nil, "CooldownOnCancel requires a cooldown")
	const allowedContexts = createStringSet(
		config.AllowedContexts or { PlayerInputServiceConstants.DEFAULT_CONTEXT_NAME },
		"config.AllowedContexts"
	)
	const allowedPlayerInputModes: { [PlayerInputModeTypes.PlayerInputModeType]: true } = {}

	if config.AllowedPlayerInputModes then
		for _, inputMode in config.AllowedPlayerInputModes do
			assert(t.string(inputMode) and isKnownPlayerInputMode(inputMode), "Bad config.AllowedPlayerInputModes")
			allowedPlayerInputModes[inputMode] = true
		end
	else
		for inputMode in inferPlayerInputModes(config.InputKeyMapList) do
			allowedPlayerInputModes[inputMode] = true
		end
	end

	local networkPolicy: PlayerInputServiceTypes.NetworkPolicy? = nil
	if config.Network then
		assert(config.Network.Capacity < math.huge and config.Network.RefillRate < math.huge, "Bad config.Network")
		const states: { [NetworkInputState]: true } = {}

		for _, state in config.Network.States do
			assert(state == "Begin" or state == "End", "Bad config.Network.States")
			states[state :: NetworkInputState] = true
		end

		assert(next(states) ~= nil, "config.Network.States cannot be empty")
		assert(not states.End or states.Begin, "config.Network.End requires Begin")

		networkPolicy = table.freeze({
			States = table.freeze(states),
			Capacity = config.Network.Capacity,
			RefillRate = config.Network.RefillRate,
		})
	end

	local conditionContainer: BindableFunction? = nil
	if config.AdorneeConditionContext then
		conditionContainer = AdorneeConditionUtils.createConditionContainer()
		const success, reason = pcall(config.AdorneeConditionContext, conditionContainer)
		if not success then
			conditionContainer:Destroy()
			error(`AdorneeConditionContext failed: {tostring(reason)}`, 2)
		end
		if not CollectionService:HasTag(conditionContainer, AdorneeConditionUtils.getRequiredTag()) then
			conditionContainer:Destroy()
			error("AdorneeConditionContext destroyed its conditionContainer", 2)
		end
	end

	return table.freeze({
		Id = config.Id,
		Name = config.Name,
		ProviderName = providerName,
		InputKeyMapList = config.InputKeyMapList,
		AllowedContexts = allowedContexts,
		AllowedPlayerInputModes = table.freeze(allowedPlayerInputModes),
		ConsumeInput = config.ConsumeInput == true,
		ContextActionPriority = config.ContextActionPriority or Enum.ContextActionPriority.Medium.Value,
		AllowWhenTextBoxFocused = config.AllowWhenTextBoxFocused == true,
		AdorneeConditionContext = conditionContainer,
		ConsumeInputWhenConditionFails = config.ConsumeInputWhenConditionFails == true,
		Network = networkPolicy,
		CooldownKey = if cooldownValue then PlayerInputServiceUtils.getActionKey(providerName, config.Name) else nil,
		CooldownType = config.CooldownType,
		CooldownValue = cooldownValue,
		CooldownOnCancel = config.CooldownOnCancel == true,
	})
end

--[=[
	Returns the compact wire code for a client-transmitted state.

	@within PlayerInputServiceUtils
	@param state InputState
	@return number?
]=]
function PlayerInputServiceUtils.toNetworkStateCode(state: InputState): number?
	assert(t.string(state), "Bad state")

	if state == "Begin" then
		return PlayerInputServiceConstants.NETWORK_STATE_BEGIN
	elseif state == "End" then
		return PlayerInputServiceConstants.NETWORK_STATE_END
	elseif state == "Cancel" then
		return PlayerInputServiceConstants.NETWORK_STATE_CANCEL
	end

	return nil
end

--[=[
	Returns the input state represented by a compact wire code.

	@within PlayerInputServiceUtils
	@param code number
	@return InputState?
]=]
function PlayerInputServiceUtils.fromNetworkStateCode(code: number): InputState?
	assert(t.number(code), "Bad code")

	if code == PlayerInputServiceConstants.NETWORK_STATE_BEGIN then
		return "Begin"
	elseif code == PlayerInputServiceConstants.NETWORK_STATE_END then
		return "End"
	elseif code == PlayerInputServiceConstants.NETWORK_STATE_CANCEL then
		return "Cancel"
	end

	return nil
end

--[=[
	Builds the next action-ID set and returns only the IDs added to and removed
	from the previous set.

	@within PlayerInputServiceUtils
	@param previousActionIds { [number]: true }
	@param currentActionIds { number }
	@return { [number]: true }
	@return { number }
	@return { number }
]=]
function PlayerInputServiceUtils.diffActionIds(
	previousActionIds: ActionIdSet,
	currentActionIds: { number }
): (ActionIdSet, { number }, { number })
	assert(t.table(previousActionIds), "Bad previousActionIds")
	assert(t.array(t.number)(currentActionIds), "Bad currentActionIds")

	const currentActionIdSet: ActionIdSet = {}
	const addedActionIds = {}
	const removedActionIds = {}

	for _, actionId in currentActionIds do
		currentActionIdSet[actionId] = true
		if previousActionIds[actionId] ~= true then
			table.insert(addedActionIds, actionId)
		end
	end

	for actionId in previousActionIds do
		if currentActionIdSet[actionId] ~= true then
			table.insert(removedActionIds, actionId)
		end
	end

	return currentActionIdSet, addedActionIds, removedActionIds
end

--[=[
	Finds an action keymap mode by its stable name.

	@within PlayerInputServiceUtils
	@param action Action
	@param inputModeName string
	@return InputMode?
]=]
function PlayerInputServiceUtils.findInputModeType(action: Action, inputModeName: string): InputMode?
	assert(t.table(action), "Bad action")
	assert(t.string(inputModeName) and inputModeName ~= "", "Bad inputModeName")

	for _, inputKeyMap in action.InputKeyMapList:GetInputKeyMaps() do
		const inputModeType = inputKeyMap:GetInputModeType()
		if inputModeType.Name == inputModeName then
			return inputModeType
		end
	end

	return nil
end

--[=[
	Returns whether an input type is present in the action's selected mode.

	@within PlayerInputServiceUtils
	@param action Action
	@param inputModeType InputModeType
	@param inputType InputType
	@return boolean
]=]
function PlayerInputServiceUtils.isInputTypeBound(
	action: Action,
	inputModeType: InputMode,
	inputType: InputType
): boolean
	assert(t.table(action), "Bad action")
	assert(t.table(inputModeType), "Bad inputModeType")
	assert(
		t.any(inputType)
			and (InputTypeUtils.isKnownInputType(inputType) or InputChordUtils.isModifierInputChord(inputType)),
		"Bad inputType"
	)

	const expectedKey = InputTypeUtils.getUniqueKeyForInputType(inputType)
	for _, boundInputType in action.InputKeyMapList:GetInputTypesList(inputModeType) do
		if InputTypeUtils.getUniqueKeyForInputType(boundInputType) == expectedKey then
			return true
		end
	end

	return false
end

--[=[
	Returns whether an InputObject matches a direct enum or modifier chord in any
	of an action's current keymaps.

	@within PlayerInputServiceUtils
	@param action Action
	@param inputObject InputObject
	@param isKeyDown (KeyCode) -> boolean
	@return boolean
]=]
function PlayerInputServiceUtils.isInputObjectBound(
	action: Action,
	inputObject: InputObject,
	isKeyDown: (Enum.KeyCode) -> boolean
): boolean
	assert(t.table(action), "Bad action")
	assert(t.instanceIsA("InputObject")(inputObject), "Bad inputObject")
	assert(t.callback(isKeyDown), "Bad isKeyDown")

	for _, inputKeyMap in action.InputKeyMapList:GetInputKeyMaps() do
		for _, inputType in inputKeyMap:GetInputTypesList() do
			if
				(isKeyCode(inputType) and inputObject.KeyCode == inputType)
				or (isUserInputType(inputType) and inputObject.UserInputType == inputType)
			then
				return true
			elseif
				InputChordUtils.isModifierInputChord(inputType)
				and inputObject.KeyCode == (inputType :: InputChordUtils.ModifierInputChord).keyCode
			then
				local modifiersHeld = true
				for _, modifier in (inputType :: InputChordUtils.ModifierInputChord).modifiers do
					if not isKeyDown(modifier) then
						modifiersHeld = false
						break
					end
				end

				if modifiersHeld then
					return true
				end
			end
		end
	end

	return false
end

--[=[
	Serializes every supported InputKeyMap input type.

	@within PlayerInputServiceUtils
	@param inputTypes { InputType }
	@return { SerializedInputType }
]=]
function PlayerInputServiceUtils.serializeInputTypes(inputTypes: { InputType }): { SerializedInputType }
	assert(t.table(inputTypes), "Bad inputTypes")

	const result = table.create(#inputTypes)

	for _, inputType in inputTypes do
		if isKeyCode(inputType) then
			table.insert(result, {
				Kind = PlayerInputServiceConstants.SERIALIZED_KEY_CODE,
				Name = EnumUtils.encodeAsString(inputType :: Enum.KeyCode),
			})
		elseif isUserInputType(inputType) then
			table.insert(result, {
				Kind = PlayerInputServiceConstants.SERIALIZED_USER_INPUT_TYPE,
				Name = EnumUtils.encodeAsString(inputType :: Enum.UserInputType),
			})
		elseif t.string(inputType) and InputTypeUtils.isKnownInputType(inputType) then
			table.insert(result, {
				Kind = PlayerInputServiceConstants.SERIALIZED_VIRTUAL_INPUT,
				Name = inputType,
			})
		elseif InputChordUtils.isModifierInputChord(inputType) then
			const modifiers = table.create(#(inputType :: InputChordUtils.ModifierInputChord).modifiers)
			for _, modifier in (inputType :: InputChordUtils.ModifierInputChord).modifiers do
				table.insert(modifiers, EnumUtils.encodeAsString(modifier))
			end

			table.insert(result, {
				Kind = PlayerInputServiceConstants.SERIALIZED_MODIFIER_CHORD,
				Name = EnumUtils.encodeAsString((inputType :: InputChordUtils.ModifierInputChord).keyCode),
				Modifiers = modifiers,
			})
		elseif SlottedTouchButtonUtils.isSlottedTouchButton(inputType) then
			table.insert(result, {
				Kind = PlayerInputServiceConstants.SERIALIZED_SLOTTED_TOUCH_BUTTON,
				Name = (inputType :: any).slotId,
			})
		else
			error("Unsupported input type")
		end
	end

	return result
end

--[=[
	Deserializes and validates binding input records.

	@within PlayerInputServiceUtils
	@param serializedInputTypes { SerializedInputType }
	@return { InputType }?
]=]
function PlayerInputServiceUtils.deserializeInputTypes(serializedInputTypes: { SerializedInputType }): { InputType }?
	if not t.array(isSerializedInputType)(serializedInputTypes) then
		return nil
	end

	const result: { InputType } = {}

	for _, serialized in serializedInputTypes do
		if serialized.Kind == PlayerInputServiceConstants.SERIALIZED_KEY_CODE then
			const keyCode = EnumUtils.toEnum(Enum.KeyCode, serialized.Name)
			if not isKeyCode(keyCode) then
				return nil
			end
			table.insert(result, keyCode :: Enum.KeyCode)
		elseif serialized.Kind == PlayerInputServiceConstants.SERIALIZED_USER_INPUT_TYPE then
			const userInputType = EnumUtils.toEnum(Enum.UserInputType, serialized.Name)
			if not isUserInputType(userInputType) then
				return nil
			end
			table.insert(result, userInputType :: Enum.UserInputType)
		elseif serialized.Kind == PlayerInputServiceConstants.SERIALIZED_VIRTUAL_INPUT then
			if not InputTypeUtils.isKnownInputType(serialized.Name) then
				return nil
			end
			table.insert(result, serialized.Name)
		elseif serialized.Kind == PlayerInputServiceConstants.SERIALIZED_MODIFIER_CHORD then
			const keyCode = EnumUtils.toEnum(Enum.KeyCode, serialized.Name)
			if not isKeyCode(keyCode) or not serialized.Modifiers then
				return nil
			end

			const modifiers: { Enum.KeyCode } = {}
			for _, modifierName in serialized.Modifiers do
				const modifier = EnumUtils.toEnum(Enum.KeyCode, modifierName)
				if not isKeyCode(modifier) then
					return nil
				end
				table.insert(modifiers, modifier :: Enum.KeyCode)
			end

			table.insert(result, InputChordUtils.createModifierInputChord(modifiers, keyCode :: Enum.KeyCode))
		elseif serialized.Kind == PlayerInputServiceConstants.SERIALIZED_SLOTTED_TOUCH_BUTTON then
			local ok, slottedTouchButton = pcall(SlottedTouchButtonUtils.createSlottedTouchButton, serialized.Name)
			if not ok then
				return nil
			end
			table.insert(result, slottedTouchButton)
		else
			return nil
		end
	end

	return result
end

--[=[
	Returns whether a value is a valid binding-override wire record.

	@within PlayerInputServiceUtils
	@param value any
	@return boolean
]=]
function PlayerInputServiceUtils.isBindingOverride(value: any): boolean
	return isBindingOverride(value)
end

--[=[
	Copies a binding override for storage or transmission.

	@within PlayerInputServiceUtils
	@param bindingOverride BindingOverride
	@return BindingOverride
]=]
function PlayerInputServiceUtils.copyBindingOverride(bindingOverride: BindingOverride): BindingOverride
	assert(isBindingOverride(bindingOverride), "Bad bindingOverride")
	return TableUtils.deepCopy(bindingOverride)
end

--[=[
	Returns whether a value is a valid initial-state response.

	@within PlayerInputServiceUtils
	@param value any
	@return boolean
]=]
function PlayerInputServiceUtils.isInitialState(value: any): boolean
	return isInitialState(value)
end

return PlayerInputServiceUtils
