--!strict
--[=[
	Unit tests for PlayerInputServiceUtils.

	@class PlayerInputServiceUtils.spec
]=]

const require = require("../../Loader").load()

const AdorneeConditionUtils = require("AdorneeConditionUtils")
const CooldownTypes = require("CooldownTypes")
const InputChordUtils = require("InputChordUtils")
const InputKeyMap = require("InputKeyMap")
const InputKeyMapList = require("InputKeyMapList")
const InputModeTypes = require("InputModeTypes")
const Jest = require("Jest")
const PlayerInputModeTypes = require("PlayerInputModeTypes")
const PlayerInputServiceUtils = require("PlayerInputServiceUtils")
const SlottedTouchButtonUtils = require("SlottedTouchButtonUtils")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("PlayerInputServiceUtils state codec", function()
	it("preserves begin, end, and cancel states", function()
		for _, state in { "Begin", "End", "Cancel" } do
			const code = PlayerInputServiceUtils.toNetworkStateCode(state :: any)
			expect(code).never.toEqual(nil)
			expect(PlayerInputServiceUtils.fromNetworkStateCode(code :: number)).toEqual(state)
		end
	end)
end)

describe("PlayerInputServiceUtils.diffActionIds", function()
	it("returns only additions and removals", function()
		const actionIdSet, addedActionIds, removedActionIds = PlayerInputServiceUtils.diffActionIds({
			[1] = true,
			[2] = true,
		}, { 2, 3 })

		expect(actionIdSet).toEqual({
			[2] = true,
			[3] = true,
		})
		expect(addedActionIds).toEqual({ 3 })
		expect(removedActionIds).toEqual({ 1 })
	end)
end)

describe("PlayerInputServiceUtils initial state", function()
	it("requires the authoritative context name", function()
		const initialState = {
			AllowedActionIds = { 1 },
			BindingOverrides = {},
			ContextName = "Gameplay",
			PolicyRevision = 2,
			BindingRevision = 0,
		}

		expect(PlayerInputServiceUtils.isInitialState(initialState)).toEqual(true)
		initialState.ContextName = ""
		expect(PlayerInputServiceUtils.isInitialState(initialState)).toEqual(false)
	end)
end)

describe("PlayerInputServiceUtils binding codec", function()
	it("round trips every supported input representation", function()
		const inputTypes = {
			Enum.KeyCode.E,
			Enum.UserInputType.MouseButton1,
			"Tap",
			InputChordUtils.createModifierInputChord({ Enum.KeyCode.LeftControl }, Enum.KeyCode.Z),
			SlottedTouchButtonUtils.createSlottedTouchButton("primary1"),
		}

		const serialized = PlayerInputServiceUtils.serializeInputTypes(inputTypes)
		const deserialized = PlayerInputServiceUtils.deserializeInputTypes(serialized)

		expect(serialized[1].Name).toEqual("Enum.KeyCode.E")
		expect(serialized[2].Name).toEqual("Enum.UserInputType.MouseButton1")
		expect(deserialized).never.toEqual(nil)
		expect(#(deserialized :: { any })).toEqual(#inputTypes)
		expect((deserialized :: { any })[1]).toEqual(Enum.KeyCode.E)
		expect((deserialized :: { any })[2]).toEqual(Enum.UserInputType.MouseButton1)
		expect((deserialized :: { any })[3]).toEqual("Tap")
		expect(((deserialized :: { any })[4] :: any).keyCode).toEqual(Enum.KeyCode.Z)
		expect(((deserialized :: { any })[5] :: any).slotId).toEqual("primary1")
	end)
end)

describe("PlayerInputServiceUtils.createAction", function()
	it("infers standard player input modes and defaults to local-only", function()
		const inputKeyMapList = InputKeyMapList.new("INTERACT", {
			InputKeyMap.new(InputModeTypes.KeyboardAndMouse, { Enum.KeyCode.E }),
			InputKeyMap.new(InputModeTypes.Gamepads, { Enum.KeyCode.ButtonX }),
		}, {
			bindingName = "Interact",
			rebindable = true,
		})

		const action = PlayerInputServiceUtils.createAction("General", {
			Id = 1,
			Name = "INTERACT",
			InputKeyMapList = inputKeyMapList,
		})

		expect(action.AllowedPlayerInputModes[PlayerInputModeTypes.KEYBOARD]).toEqual(true)
		expect(action.AllowedPlayerInputModes[PlayerInputModeTypes.GAMEPAD]).toEqual(true)
		expect(action.AllowedPlayerInputModes[PlayerInputModeTypes.TOUCH]).toEqual(nil)
		expect(action.Network).toEqual(nil)

		inputKeyMapList:Destroy()
	end)

	it("builds one move-owned adornee condition context", function()
		const inputKeyMapList = InputKeyMapList.new("PUNCH", {
			InputKeyMap.new(InputModeTypes.KeyboardAndMouse, { Enum.UserInputType.MouseButton1 }),
		}, {
			bindingName = "Punch",
			rebindable = true,
		})
		local receivedConditionContainer: BindableFunction? = nil

		const action = PlayerInputServiceUtils.createAction("Combat", {
			Id = 2,
			Name = "PUNCH",
			InputKeyMapList = inputKeyMapList,
			AdorneeConditionContext = function(conditionContainer)
				receivedConditionContainer = conditionContainer
				AdorneeConditionUtils.createRequiredAttribute("CanAttack", true).Parent = conditionContainer
			end,
			ConsumeInputWhenConditionFails = true,
		})

		expect(action.AdorneeConditionContext).toEqual(receivedConditionContainer)
		expect(action.AdorneeConditionContext).never.toEqual(nil)
		expect(action.ConsumeInputWhenConditionFails).toEqual(true)

		const conditionContainer = action.AdorneeConditionContext :: BindableFunction
		conditionContainer:Destroy()
		inputKeyMapList:Destroy()
	end)

	it("builds one stable move-specific cooldown definition", function()
		const inputKeyMapList = InputKeyMapList.fromInputKeys({ Enum.KeyCode.Q })
		const action = PlayerInputServiceUtils.createAction("Combat", {
			Id = 3,
			Name = "DASH",
			InputKeyMapList = inputKeyMapList,
			CooldownType = CooldownTypes.Default,
			CooldownValue = {
				Duration = 2,
			},
			CooldownOnCancel = true,
		})

		expect(action.CooldownKey).toEqual("Combat.DASH")
		expect(action.CooldownType).toEqual(CooldownTypes.Default)
		expect(action.CooldownValue).toEqual({
			Duration = 2,
		})
		expect(action.CooldownOnCancel).toEqual(true)
		expect(table.isfrozen(action.CooldownValue :: any)).toEqual(true)

		inputKeyMapList:Destroy()
	end)

	it("requires a complete valid move cooldown pair", function()
		const inputKeyMapList = InputKeyMapList.fromInputKeys({ Enum.KeyCode.Q })
		const missingValueSucceeded = pcall(function()
			PlayerInputServiceUtils.createAction("Combat", {
				Id = 4,
				Name = "INVALID_DASH",
				InputKeyMapList = inputKeyMapList,
				CooldownType = CooldownTypes.Default,
			})
		end)
		const invalidBurstSucceeded = pcall(function()
			PlayerInputServiceUtils.createAction("Combat", {
				Id = 5,
				Name = "INVALID_PUNCH",
				InputKeyMapList = inputKeyMapList,
				CooldownType = CooldownTypes.Burst,
				CooldownValue = {
					Duration = 0.5,
					Count = 1,
					Window = 3,
					PenaltyDuration = 3,
				},
			})
		end)
		const cancelWithoutCooldownSucceeded = pcall(function()
			PlayerInputServiceUtils.createAction("Combat", {
				Id = 6,
				Name = "INVALID_CANCEL_POLICY",
				InputKeyMapList = inputKeyMapList,
				CooldownOnCancel = true,
			})
		end)

		expect(missingValueSucceeded).toEqual(false)
		expect(invalidBurstSucceeded).toEqual(false)
		expect(cancelWithoutCooldownSucceeded).toEqual(false)

		inputKeyMapList:Destroy()
	end)
end)
