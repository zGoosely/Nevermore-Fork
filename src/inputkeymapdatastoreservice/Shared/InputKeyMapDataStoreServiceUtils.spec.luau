--!strict
--[=[
	Unit tests for persisted input-keymap codecs and immutable updates.

	@class InputKeyMapDataStoreServiceUtils.spec
]=]

const require = require("../../Loader").load()

const InputChordUtils = require("InputChordUtils")
const InputKeyMapDataStoreServiceUtils = require("InputKeyMapDataStoreServiceUtils")
const InputModeTypes = require("InputModeTypes")
const Jest = require("Jest")
const SlottedTouchButtonUtils = require("SlottedTouchButtonUtils")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("InputKeyMapDataStoreServiceUtils", function()
	it("round trips every supported input representation", function()
		const inputTypes = {
			Enum.KeyCode.E,
			Enum.UserInputType.MouseButton1,
			"Tap",
			InputChordUtils.createModifierInputChord({ Enum.KeyCode.LeftControl }, Enum.KeyCode.Z),
			SlottedTouchButtonUtils.createSlottedTouchButton("primary1"),
		}

		const serialized = InputKeyMapDataStoreServiceUtils.serializeInputTypes(inputTypes)
		const deserialized = InputKeyMapDataStoreServiceUtils.deserializeInputTypes(serialized)

		expect(deserialized).never.toEqual(nil)
		expect(#(deserialized :: { any })).toEqual(#inputTypes)
		expect((deserialized :: { any })[1]).toEqual(Enum.KeyCode.E)
		expect((deserialized :: { any })[2]).toEqual(Enum.UserInputType.MouseButton1)
		expect((deserialized :: { any })[3]).toEqual("Tap")
		expect(((deserialized :: { any })[4] :: any).keyCode).toEqual(Enum.KeyCode.Z)
		expect(((deserialized :: { any })[5] :: any).slotId).toEqual("primary1")
	end)

	it("validates decoded inputs against their input mode", function()
		expect(
			InputKeyMapDataStoreServiceUtils.areInputTypesValidForMode(
				InputModeTypes.KeyboardAndMouse,
				{ Enum.KeyCode.E }
			)
		).toEqual(true)
		expect(InputKeyMapDataStoreServiceUtils.areInputTypesValidForMode(InputModeTypes.Gamepads, { Enum.KeyCode.E })).toEqual(
			false
		)
		expect(
			InputKeyMapDataStoreServiceUtils.areInputTypesValidForMode(
				InputModeTypes.Touch,
				{ SlottedTouchButtonUtils.createSlottedTouchButton("primary1") }
			)
		).toEqual(true)
	end)

	it("replaces and clears one binding without mutating the source", function()
		const original = {
			{
				ProviderName = "General",
				ListName = "INTERACT",
				InputModeName = "KeyboardAndMouse",
				InputTypes = InputKeyMapDataStoreServiceUtils.serializeInputTypes({ Enum.KeyCode.E }),
			},
		}
		const replacement = InputKeyMapDataStoreServiceUtils.applyBindingRequest(original, {
			ProviderName = "General",
			ListName = "INTERACT",
			InputModeName = "KeyboardAndMouse",
			InputTypes = InputKeyMapDataStoreServiceUtils.serializeInputTypes({ Enum.KeyCode.F }),
			Clear = false,
		})

		expect(original[1].InputTypes[1].Name).toEqual("Enum.KeyCode.E")
		expect(replacement[1].InputTypes[1].Name).toEqual("Enum.KeyCode.F")

		const cleared = InputKeyMapDataStoreServiceUtils.applyBindingRequest(replacement, {
			ProviderName = "General",
			ListName = "INTERACT",
			InputModeName = "KeyboardAndMouse",
			InputTypes = {},
			Clear = true,
		})
		expect(#cleared).toEqual(0)
	end)
end)
