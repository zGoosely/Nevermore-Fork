--[=[
    @class DeviceUtils
]=]

const require = require("../Loader").load()

const Brio = require("Brio")
const Observable = require("Observable")
const InputCategorizer = require("InputCategorizer")
const InputCategoryTypes = require("InputCategoryTypes")
const ValueObject = require("ValueObject")

const DeviceUtils = {}
DeviceUtils.CurrentValue = ValueObject.new(InputCategorizer.getLastInputCategory(), "string")
DeviceUtils.Changed = DeviceUtils.CurrentValue.Changed

InputCategorizer.lastInputCategoryChanged:Connect(function(newCategory)
	DeviceUtils.CurrentValue.Value = newCategory
end)

--[=[
	Observes the current platform as a string. Emits the current platform immediately upon subscription.

	@within DeviceUtils
	@return string
]=]
function DeviceUtils.Observe(): Observable.Observable<string>
	return DeviceUtils.CurrentValue:Observe()
end

--[=[
	Observes the current platform as a string. Emits the current platform immediately upon subscription.

	@within DeviceUtils
	@return string
]=]
function DeviceUtils.ObserveBrio(): Observable.Observable<Brio.Brio<string>>
	return DeviceUtils.CurrentValue:ObserveBrio()
end

--[=[
	Returns whether the player is currently using a **Gamepad**.

	@within DeviceUtils
	@return boolean
]=]
function DeviceUtils.IsGamepad(): boolean
	return DeviceUtils.CurrentValue.Value == InputCategorizer.InputCategory.Gamepad
end

--[=[
	Returns whether the player is currently using **Keyboard and Mouse**.

	@within DeviceUtils
	@return boolean
]=]
function DeviceUtils.IsKeyboardMouse(): boolean
	return DeviceUtils.CurrentValue.Value == InputCategorizer.InputCategory.KeyboardAndMouse
end

--[=[
	Returns whether the player is currently using a **Touch DeviceUtils**.

	@within DeviceUtils
	@return boolean
]=]
function DeviceUtils.IsTouch(): boolean
	return DeviceUtils.CurrentValue.Value == InputCategorizer.InputCategory.Touch
end

return DeviceUtils
