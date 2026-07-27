--!strict
--[=[
	Unit tests for priority input contexts and restrictions.

	@class PlayerInputPolicyModel.spec
]=]

const require = require("../../Loader").load()

const InputKeyMapList = require("InputKeyMapList")
const Jest = require("Jest")
const PlayerInputActionRegistryServiceShared = require("PlayerInputActionRegistryServiceShared")
const PlayerInputPolicyModel = require("PlayerInputPolicyModel")
const PlayerInputResults = require("PlayerInputResults")
const PlayerInputServiceUtils = require("PlayerInputServiceUtils")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

local function createRegistryAndAction()
	const registry = setmetatable({}, { __index = PlayerInputActionRegistryServiceShared }) :: any
	registry:Init({})

	const inputKeyMapList = InputKeyMapList.fromInputKeys({ Enum.KeyCode.E })
	const action = PlayerInputServiceUtils.createAction("General", {
		Id = 1,
		Name = "INTERACT",
		InputKeyMapList = inputKeyMapList,
		AllowedContexts = { "Default", "Gameplay" },
	})
	const provider = {
		GetActions = function()
			return { action }
		end,
		GetContexts = function()
			return {
				table.freeze({ Name = "Gameplay", Priority = 10 }),
				table.freeze({ Name = "Menu", Priority = 20 }),
			}
		end,
	}
	registry:RegisterProvider(provider)
	registry:Start()

	return registry, action, inputKeyMapList
end

describe("PlayerInputPolicyModel", function()
	it("uses the highest priority context and most recent restriction tie", function()
		const registry, action, inputKeyMapList = createRegistryAndAction()
		const policy = PlayerInputPolicyModel.new(registry)

		expect(policy:GetCurrentContextName()).toEqual("Default")
		expect(policy:IsActionAllowed(action)).toEqual(true)

		const removeGameplay = policy:PushContext("Gameplay")
		expect(policy:GetCurrentContextName()).toEqual("Gameplay")
		expect(policy:IsActionAllowed(action)).toEqual(true)

		const removeMenu = policy:PushContext("Menu")
		expect(policy:GetCurrentContextName()).toEqual("Menu")
		expect(policy:IsActionAllowed(action)).toEqual(false)
		expect(policy:GetActionDenialResult(action)).toEqual(PlayerInputResults.ContextDenied)

		removeMenu()
		expect(policy:GetCurrentContextName()).toEqual("Gameplay")
		expect(policy:IsActionAllowed(action)).toEqual(true)

		const removeDeny = policy:PushRestriction({
			Priority = 100,
			Actions = { action },
			Allowed = false,
		})
		expect(policy:IsActionAllowed(action)).toEqual(false)
		expect(policy:GetActionDenialResult(action)).toEqual(PlayerInputResults.RestrictionDenied)

		const removeAllow = policy:PushRestriction({
			Priority = 100,
			Actions = { action.Id },
			Allowed = true,
		})
		expect(policy:IsActionAllowed(action)).toEqual(true)

		removeAllow()
		expect(policy:IsActionAllowed(action)).toEqual(false)

		removeDeny()
		removeGameplay()
		expect(policy:GetCurrentContextName()).toEqual("Default")
		policy:Destroy()
		registry:Destroy()
		inputKeyMapList:Destroy()
	end)
end)
