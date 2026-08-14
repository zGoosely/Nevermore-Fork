--!strict
--[=[
	Validates, serializes, and updates persisted input-keymap bindings.

	@util InputKeyMapDataStoreServiceUtils
]=]
const EnumUtils = require("@game/ReplicatedStorage/Packages/EnumUtils")
const InputChordUtils = require("@game/ReplicatedStorage/Packages/InputChordUtils")
const InputKeyMap = require("@game/ReplicatedStorage/Packages/InputKeyMap")
const InputKeyMapDataStoreServiceConstants = require("./InputKeyMapDataStoreServiceConstants")
const InputKeyMapDataStoreServiceTypes = require("./InputKeyMapDataStoreServiceTypes")
const InputKeyMapList = require("@game/ReplicatedStorage/Packages/InputKeyMapList")
const InputModeType = require("@game/ReplicatedStorage/Packages/InputModeType")
const InputModeTypes = require("@game/ReplicatedStorage/Packages/InputModeTypes")
const InputTypeUtils = require("@game/ReplicatedStorage/Packages/InputTypeUtils")
const SlottedTouchButtonUtils = require("@game/ReplicatedStorage/Packages/SlottedTouchButtonUtils")
const Squash = require("@game/ReplicatedStorage/Packages/Squash")
const TableUtils = require("@game/ReplicatedStorage/Packages/TableUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

type Binding = InputKeyMapDataStoreServiceTypes.Binding
type BindingRequest = InputKeyMapDataStoreServiceTypes.BindingRequest
type Bindings = InputKeyMapDataStoreServiceTypes.Bindings
type InputType = InputTypeUtils.InputType
type SerializedInputType = InputKeyMapDataStoreServiceTypes.SerializedInputType

const isKeyCode = t.enum(Enum.KeyCode)
const isUserInputType = t.enum(Enum.UserInputType)
const isSerializedInputTypeShape = t.strictInterface({
	Kind = t.number,
	Name = t.string,
	Modifiers = t.optional(t.array(t.string)),
})
const isBindingShape = t.strictInterface({
	ProviderName = t.string,
	ListName = t.string,
	InputModeName = t.string,
	InputTypes = t.table,
})
const isBindingRequestShape = t.strictInterface({
	ProviderName = t.string,
	ListName = t.string,
	InputModeName = t.string,
	InputTypes = t.table,
	Clear = t.boolean,
})

const InputKeyMapDataStoreServiceUtils = {}

const function isBoundedName(value: any, maximumLength: number): boolean
	return t.string(value) and value ~= "" and #value <= maximumLength
end

const function isSerializedKind(value: number): boolean
	return value == InputKeyMapDataStoreServiceConstants.SERIALIZED_KEY_CODE
		or value == InputKeyMapDataStoreServiceConstants.SERIALIZED_USER_INPUT_TYPE
		or value == InputKeyMapDataStoreServiceConstants.SERIALIZED_VIRTUAL_INPUT
		or value == InputKeyMapDataStoreServiceConstants.SERIALIZED_MODIFIER_CHORD
		or value == InputKeyMapDataStoreServiceConstants.SERIALIZED_SLOTTED_TOUCH_BUTTON
end

const function copyBinding(binding: Binding): Binding
	return TableUtils.deepCopy(binding)
end

--[=[
	Returns whether a value is one bounded, network-safe serialized input type.

	@within InputKeyMapDataStoreServiceUtils
	@param value any
	@return boolean
]=]
function InputKeyMapDataStoreServiceUtils.isSerializedInputType(value: any): boolean
	if not isSerializedInputTypeShape(value) then
		return false
	end
	if not t.integer(value.Kind) or not isSerializedKind(value.Kind) then
		return false
	end
	if not isBoundedName(value.Name, InputKeyMapDataStoreServiceConstants.MAX_SERIALIZED_INPUT_NAME_LENGTH) then
		return false
	end
	if value.Modifiers and #value.Modifiers > InputKeyMapDataStoreServiceConstants.MAX_MODIFIERS then
		return false
	end
	for _, modifierName in value.Modifiers or {} do
		if not isBoundedName(modifierName, InputKeyMapDataStoreServiceConstants.MAX_SERIALIZED_INPUT_NAME_LENGTH) then
			return false
		end
	end

	if value.Kind == InputKeyMapDataStoreServiceConstants.SERIALIZED_MODIFIER_CHORD then
		return value.Modifiers ~= nil
	end

	return value.Modifiers == nil
end

--[=[
	Returns whether a value is one persisted binding record.

	@within InputKeyMapDataStoreServiceUtils
	@param value any
	@return boolean
]=]
function InputKeyMapDataStoreServiceUtils.isBinding(value: any): boolean
	return isBindingShape(value)
		and isBoundedName(value.ProviderName, InputKeyMapDataStoreServiceConstants.MAX_NAME_LENGTH)
		and isBoundedName(value.ListName, InputKeyMapDataStoreServiceConstants.MAX_NAME_LENGTH)
		and isBoundedName(value.InputModeName, InputKeyMapDataStoreServiceConstants.MAX_NAME_LENGTH)
		and #value.InputTypes <= InputKeyMapDataStoreServiceConstants.MAX_INPUT_TYPES
		and t.array(InputKeyMapDataStoreServiceUtils.isSerializedInputType)(value.InputTypes)
end

--[=[
	Returns whether a value is a client binding request.

	@within InputKeyMapDataStoreServiceUtils
	@param value any
	@return boolean
]=]
function InputKeyMapDataStoreServiceUtils.isBindingRequest(value: any): boolean
	if not isBindingRequestShape(value) then
		return false
	end
	if value.Clear and #value.InputTypes ~= 0 then
		return false
	end

	return InputKeyMapDataStoreServiceUtils.isBinding({
		ProviderName = value.ProviderName,
		ListName = value.ListName,
		InputModeName = value.InputModeName,
		InputTypes = value.InputTypes,
	})
end

--[=[
	Returns whether a value is a bounded array of persisted bindings.

	@within InputKeyMapDataStoreServiceUtils
	@param value any
	@return boolean
]=]
function InputKeyMapDataStoreServiceUtils.isBindings(value: any): boolean
	if
		not t.table(value)
		or #value > InputKeyMapDataStoreServiceConstants.MAX_BINDINGS
		or not t.array(InputKeyMapDataStoreServiceUtils.isBinding)(value)
	then
		return false
	end

	const seen: { [string]: { [string]: { [string]: true } } } = {}
	for _, binding in value do
		const providerBindings = seen[binding.ProviderName] or {}
		seen[binding.ProviderName] = providerBindings
		const listBindings = providerBindings[binding.ListName] or {}
		providerBindings[binding.ListName] = listBindings
		if listBindings[binding.InputModeName] then
			return false
		end
		listBindings[binding.InputModeName] = true
	end

	return true
end

--[=[
	Returns the Squash codec a consuming profile should use for `InputKeyMapBindings`.

	@within InputKeyMapDataStoreServiceUtils
	@return any
]=]
function InputKeyMapDataStoreServiceUtils.getBindingsSchema(): any
	const serializedInputTypeSchema = Squash.record({
		Kind = Squash.u8(),
		Name = Squash.string(),
		Modifiers = Squash.opt(Squash.array(Squash.string())),
	})

	return Squash.array(Squash.record({
		ProviderName = Squash.string(),
		ListName = Squash.string(),
		InputModeName = Squash.string(),
		InputTypes = Squash.array(serializedInputTypeSchema),
	}))
end

--[=[
	Returns whether a selected PlayerDataStoreService profile declares the required binding array.

	@within InputKeyMapDataStoreServiceUtils
	@param profileDefinition any
	@return boolean
]=]
function InputKeyMapDataStoreServiceUtils.isCompatibleProfileDefinition(profileDefinition: any): boolean
	return t.table(profileDefinition)
		and t.table(profileDefinition.Template)
		and InputKeyMapDataStoreServiceUtils.isBindings(
			profileDefinition.Template[InputKeyMapDataStoreServiceConstants.PROFILE_PATH]
		)
end

--[=[
	Serializes every supported InputKeyMap input type into datastore-safe records.

	@within InputKeyMapDataStoreServiceUtils
	@param inputTypes { InputType }
	@return { SerializedInputType }
]=]
function InputKeyMapDataStoreServiceUtils.serializeInputTypes(inputTypes: { InputType }): { SerializedInputType }
	assert(t.table(inputTypes), "Bad inputTypes")
	assert(#inputTypes <= InputKeyMapDataStoreServiceConstants.MAX_INPUT_TYPES, "Too many inputTypes")

	const result: { SerializedInputType } = {}
	for _, inputType in inputTypes do
		if isKeyCode(inputType) then
			table.insert(result, {
				Kind = InputKeyMapDataStoreServiceConstants.SERIALIZED_KEY_CODE,
				Name = EnumUtils.encodeAsString(inputType :: Enum.KeyCode),
			})
		elseif isUserInputType(inputType) then
			table.insert(result, {
				Kind = InputKeyMapDataStoreServiceConstants.SERIALIZED_USER_INPUT_TYPE,
				Name = EnumUtils.encodeAsString(inputType :: Enum.UserInputType),
			})
		elseif t.string(inputType) and InputTypeUtils.isKnownInputType(inputType) then
			table.insert(result, {
				Kind = InputKeyMapDataStoreServiceConstants.SERIALIZED_VIRTUAL_INPUT,
				Name = inputType,
			})
		elseif InputChordUtils.isModifierInputChord(inputType) then
			const chord = inputType :: InputChordUtils.ModifierInputChord
			assert(#chord.modifiers <= InputKeyMapDataStoreServiceConstants.MAX_MODIFIERS, "Too many modifiers")

			const modifiers = table.create(#chord.modifiers)
			for _, modifier in chord.modifiers do
				assert(isKeyCode(modifier), "Bad inputType.modifiers")
				table.insert(modifiers, EnumUtils.encodeAsString(modifier))
			end

			table.insert(result, {
				Kind = InputKeyMapDataStoreServiceConstants.SERIALIZED_MODIFIER_CHORD,
				Name = EnumUtils.encodeAsString(chord.keyCode),
				Modifiers = modifiers,
			})
		elseif SlottedTouchButtonUtils.isSlottedTouchButton(inputType) then
			const slotId = (inputType :: any).slotId
			assert(
				isBoundedName(slotId, InputKeyMapDataStoreServiceConstants.MAX_SERIALIZED_INPUT_NAME_LENGTH),
				"Bad inputType.slotId"
			)
			table.insert(result, {
				Kind = InputKeyMapDataStoreServiceConstants.SERIALIZED_SLOTTED_TOUCH_BUTTON,
				Name = slotId,
			})
		else
			error("Unsupported inputType")
		end
	end

	return result
end

--[=[
	Deserializes and validates datastore-safe input records.

	@within InputKeyMapDataStoreServiceUtils
	@param serializedInputTypes { SerializedInputType }
	@return { InputType }?
]=]
function InputKeyMapDataStoreServiceUtils.deserializeInputTypes(
	serializedInputTypes: { SerializedInputType }
): { InputType }?
	if #serializedInputTypes > InputKeyMapDataStoreServiceConstants.MAX_INPUT_TYPES then
		return nil
	end
	if not t.array(InputKeyMapDataStoreServiceUtils.isSerializedInputType)(serializedInputTypes) then
		return nil
	end

	const result: { InputType } = {}
	for _, serializedInputType in serializedInputTypes do
		if serializedInputType.Kind == InputKeyMapDataStoreServiceConstants.SERIALIZED_KEY_CODE then
			const keyCode = EnumUtils.toEnum(Enum.KeyCode, serializedInputType.Name)
			if not isKeyCode(keyCode) then
				return nil
			end
			table.insert(result, keyCode :: Enum.KeyCode)
		elseif serializedInputType.Kind == InputKeyMapDataStoreServiceConstants.SERIALIZED_USER_INPUT_TYPE then
			const userInputType = EnumUtils.toEnum(Enum.UserInputType, serializedInputType.Name)
			if not isUserInputType(userInputType) then
				return nil
			end
			table.insert(result, userInputType :: Enum.UserInputType)
		elseif serializedInputType.Kind == InputKeyMapDataStoreServiceConstants.SERIALIZED_VIRTUAL_INPUT then
			if not InputTypeUtils.isKnownInputType(serializedInputType.Name) then
				return nil
			end
			table.insert(result, serializedInputType.Name)
		elseif serializedInputType.Kind == InputKeyMapDataStoreServiceConstants.SERIALIZED_MODIFIER_CHORD then
			const keyCode = EnumUtils.toEnum(Enum.KeyCode, serializedInputType.Name)
			if not isKeyCode(keyCode) or not serializedInputType.Modifiers then
				return nil
			end

			const modifiers: { Enum.KeyCode } = {}
			for _, modifierName in serializedInputType.Modifiers do
				const modifier = EnumUtils.toEnum(Enum.KeyCode, modifierName)
				if not isKeyCode(modifier) then
					return nil
				end
				table.insert(modifiers, modifier :: Enum.KeyCode)
			end
			table.insert(result, InputChordUtils.createModifierInputChord(modifiers, keyCode :: Enum.KeyCode))
		elseif serializedInputType.Kind == InputKeyMapDataStoreServiceConstants.SERIALIZED_SLOTTED_TOUCH_BUTTON then
			const success, slottedTouchButton =
				pcall(SlottedTouchButtonUtils.createSlottedTouchButton, serializedInputType.Name)
			if not success then
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
	Returns whether decoded input types belong to the requested input mode.

	@within InputKeyMapDataStoreServiceUtils
	@param inputModeType InputModeType
	@param inputTypes { InputType }
	@return boolean
]=]
function InputKeyMapDataStoreServiceUtils.areInputTypesValidForMode(
	inputModeType: InputModeType.InputModeType,
	inputTypes: { InputType }
): boolean
	assert(t.table(inputModeType) and InputModeType.isInputModeType(inputModeType), "Bad inputModeType")
	assert(t.table(inputTypes), "Bad inputTypes")

	for _, inputType in inputTypes do
		if isKeyCode(inputType) or isUserInputType(inputType) then
			if not inputModeType:IsValid(inputType) then
				return false
			end
		elseif InputChordUtils.isModifierInputChord(inputType) then
			const chord = inputType :: InputChordUtils.ModifierInputChord
			if not inputModeType:IsValid(chord.keyCode) then
				return false
			end
			for _, modifier in chord.modifiers do
				if not inputModeType:IsValid(modifier) then
					return false
				end
			end
		elseif t.string(inputType) and InputTypeUtils.isKnownInputType(inputType) then
			if inputModeType ~= InputModeTypes.Touch and not inputModeType:IsValid(inputType) then
				return false
			end
		elseif SlottedTouchButtonUtils.isSlottedTouchButton(inputType) then
			if inputModeType ~= InputModeTypes.Touch then
				return false
			end
		else
			return false
		end
	end

	return true
end

--[=[
	Finds the keymap in a list with the requested input-mode name.

	@within InputKeyMapDataStoreServiceUtils
	@param inputKeyMapList InputKeyMapList
	@param inputModeName string
	@return InputKeyMap?
]=]
function InputKeyMapDataStoreServiceUtils.findInputKeyMap(
	inputKeyMapList: InputKeyMapList.InputKeyMapList,
	inputModeName: string
): InputKeyMap.InputKeyMap?
	assert(t.table(inputKeyMapList) and InputKeyMapList.isInputKeyMapList(inputKeyMapList), "Bad inputKeyMapList")
	assert(t.string(inputModeName) and inputModeName ~= "", "Bad inputModeName")

	for _, inputKeyMap in inputKeyMapList:GetInputKeyMaps() do
		if inputKeyMap:GetInputModeType().Name == inputModeName then
			return inputKeyMap
		end
	end

	return nil
end

--[=[
	Finds one persisted override by provider, list, and input-mode name.

	@within InputKeyMapDataStoreServiceUtils
	@param bindings Bindings
	@param providerName string
	@param listName string
	@param inputModeName string
	@return Binding?
]=]
function InputKeyMapDataStoreServiceUtils.findBinding(
	bindings: Bindings,
	providerName: string,
	listName: string,
	inputModeName: string
): Binding?
	assert(InputKeyMapDataStoreServiceUtils.isBindings(bindings), "Bad bindings")
	assert(t.string(providerName), "Bad providerName")
	assert(t.string(listName), "Bad listName")
	assert(t.string(inputModeName), "Bad inputModeName")

	for _, binding in bindings do
		if
			binding.ProviderName == providerName
			and binding.ListName == listName
			and binding.InputModeName == inputModeName
		then
			return binding
		end
	end

	return nil
end

--[=[
	Returns a copied binding array with one request applied idempotently.

	@within InputKeyMapDataStoreServiceUtils
	@param bindings Bindings
	@param request BindingRequest
	@return Bindings
]=]
function InputKeyMapDataStoreServiceUtils.applyBindingRequest(bindings: Bindings, request: BindingRequest): Bindings
	assert(InputKeyMapDataStoreServiceUtils.isBindings(bindings), "Bad bindings")
	assert(InputKeyMapDataStoreServiceUtils.isBindingRequest(request), "Bad request")

	const result: Bindings = {}
	local replaced = false
	for _, binding in bindings do
		const matches = binding.ProviderName == request.ProviderName
			and binding.ListName == request.ListName
			and binding.InputModeName == request.InputModeName
		if matches then
			if not request.Clear and not replaced then
				table.insert(result, {
					ProviderName = request.ProviderName,
					ListName = request.ListName,
					InputModeName = request.InputModeName,
					InputTypes = TableUtils.deepCopy(request.InputTypes),
				})
				replaced = true
			end
		else
			table.insert(result, copyBinding(binding))
		end
	end

	if not request.Clear and not replaced then
		assert(#result < InputKeyMapDataStoreServiceConstants.MAX_BINDINGS, "Too many bindings")
		table.insert(result, {
			ProviderName = request.ProviderName,
			ListName = request.ListName,
			InputModeName = request.InputModeName,
			InputTypes = TableUtils.deepCopy(request.InputTypes),
		})
	end

	return result
end

--[=[
	Returns whether two serialized input lists are deeply equivalent.

	@within InputKeyMapDataStoreServiceUtils
	@param left { SerializedInputType }
	@param right { SerializedInputType }
	@return boolean
]=]
function InputKeyMapDataStoreServiceUtils.areSerializedInputTypesEquivalent(
	left: { SerializedInputType },
	right: { SerializedInputType }
): boolean
	assert(t.array(InputKeyMapDataStoreServiceUtils.isSerializedInputType)(left), "Bad left")
	assert(t.array(InputKeyMapDataStoreServiceUtils.isSerializedInputType)(right), "Bad right")

	return TableUtils.deepEquivalent(left, right)
end

return InputKeyMapDataStoreServiceUtils
