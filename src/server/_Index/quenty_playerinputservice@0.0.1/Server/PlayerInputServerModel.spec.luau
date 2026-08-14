--!strict
--[=[
	Unit tests for authoritative semantic input state transitions.

	@class PlayerInputServerModel.spec
]=]
const InputKeyMap = require("@game/ReplicatedStorage/Packages/InputKeyMap")
const InputKeyMapList = require("@game/ReplicatedStorage/Packages/InputKeyMapList")
const InputModeTypes = require("@game/ReplicatedStorage/Packages/InputModeTypes")
const Jest = require("@game/ReplicatedStorage/Packages/Jest")
const PlayerInputActionRegistryServiceShared = require("../Shared/PlayerInputActionRegistryServiceShared")
const PlayerInputModeTypes = require("@game/ReplicatedStorage/Packages/PlayerInputModeTypes")
const PlayerInputResults = require("../Shared/PlayerInputResults")
const PlayerInputServerModel = require("./PlayerInputServerModel")
const PlayerInputServiceUtils = require("../Shared/PlayerInputServiceUtils")
const ValueObject = require("@game/ReplicatedStorage/Packages/ValueObject")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("PlayerInputServerModel", function()
	it("accepts legal held transitions and rejects duplicates", function()
		const registry = setmetatable({}, { __index = PlayerInputActionRegistryServiceShared }) :: any
		registry:Init({})

		const inputKeyMapList = InputKeyMapList.new("BLOCK", {
			InputKeyMap.new(InputModeTypes.KeyboardAndMouse, { Enum.KeyCode.F }),
		}, {
			bindingName = "Block",
			rebindable = true,
		})
		const action = PlayerInputServiceUtils.createAction("Combat", {
			Id = 10,
			Name = "BLOCK",
			InputKeyMapList = inputKeyMapList,
			AllowedContexts = { "Default", "Gameplay" },
			Network = {
				States = { "Begin", "End" },
				Capacity = 10,
				RefillRate = 10,
			},
		})
		registry:RegisterProvider({
			GetActions = function()
				return { action }
			end,
			GetContexts = function()
				return {
					table.freeze({
						Name = "Gameplay",
						Priority = 10,
					}),
				}
			end,
		})
		registry:Start()

		const inputMode = ValueObject.new(PlayerInputModeTypes.KEYBOARD)
		const playerInputModeService = {
			ObservePlayerInputType = function()
				return inputMode:Observe()
			end,
		}
		const player = Instance.new("Player")
		const states = {}
		const policyContexts = {}
		const model = PlayerInputServerModel.new(
			player,
			registry,
			playerInputModeService :: any,
			100,
			100,
			function(_action, state)
				table.insert(states, state)
			end,
			function(_revision, _addedActionIds, _removedActionIds, contextName)
				table.insert(policyContexts, contextName)
			end
		)

		const defaultState = model:GetInitialState()
		expect(defaultState.ContextName).toEqual("Default")
		const removeGameplay = model:PushContext("Gameplay")
		const gameplayState = model:GetInitialState()
		expect(gameplayState.ContextName).toEqual("Gameplay")
		expect(gameplayState.PolicyRevision).toEqual(defaultState.PolicyRevision + 1)
		expect(policyContexts[#policyContexts]).toEqual("Gameplay")
		removeGameplay()
		expect(model:GetInitialState().ContextName).toEqual("Default")
		expect(policyContexts[#policyContexts]).toEqual("Default")

		inputMode.Value = PlayerInputModeTypes.GAMEPAD
		expect(model:TryInput(action, "Begin")).toEqual(PlayerInputResults.InputModeDenied)
		inputMode.Value = PlayerInputModeTypes.KEYBOARD

		model:ProcessInput(action.Id, 0)
		model:ProcessInput(action.Id, 0)
		model:ProcessInput(action.Id, 1)
		model:ProcessInput(action.Id, 1)

		expect(states).toEqual({ "Begin", "End" })
		expect(model:IsInputHeld(action)).toEqual(false)

		model:ProcessInput(action.Id, 0)
		expect(model:IsInputHeld(action)).toEqual(true)
		model:ProcessInput(action.Id, 2)
		expect(model:IsInputHeld(action)).toEqual(false)
		expect(states).toEqual({ "Begin", "End", "Begin", "Cancel" })

		model:ProcessInput(action.Id, 0)
		expect(model:ForceRelease(action)).toEqual(true)
		expect(model:IsInputHeld(action)).toEqual(false)
		expect(states).toEqual({ "Begin", "End", "Begin", "Cancel", "Begin", "Cancel" })

		model:ProcessInput(action.Id, 0)
		expect(model:ForceReleaseAll()).toEqual(1)
		expect(states).toEqual({ "Begin", "End", "Begin", "Cancel", "Begin", "Cancel", "Begin", "Cancel" })

		model:ProcessInput(action.Id, 0)
		model:Destroy()
		expect(states).toEqual({
			"Begin",
			"End",
			"Begin",
			"Cancel",
			"Begin",
			"Cancel",
			"Begin",
			"Cancel",
			"Begin",
			"Cancel",
		})

		inputMode:Destroy()
		registry:Destroy()
		inputKeyMapList:Destroy()
		player:Destroy()
	end)
end)
