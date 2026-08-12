--!strict
--[=[
	Unit tests for authoritative NPC input policy and detailed results.

	@class PlayerInputActorModel.spec
]=]

const require = require("../../Loader").load()

const AdorneeConditionUtils = require("AdorneeConditionUtils")
const InputKeyMap = require("InputKeyMap")
const InputKeyMapList = require("InputKeyMapList")
const InputModeTypes = require("InputModeTypes")
const Jest = require("Jest")
const PlayerInputActionRegistryServiceShared = require("PlayerInputActionRegistryServiceShared")
const PlayerInputActorModel = require("PlayerInputActorModel")
const PlayerInputResults = require("PlayerInputResults")
const PlayerInputServiceUtils = require("PlayerInputServiceUtils")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("PlayerInputActorModel", function()
	it("processes NPC held states without a player input mode", function()
		const registry = setmetatable({}, { __index = PlayerInputActionRegistryServiceShared }) :: any
		registry:Init({})

		const inputKeyMapList = InputKeyMapList.new("NPC_BLOCK", {
			InputKeyMap.new(InputModeTypes.KeyboardAndMouse, { Enum.KeyCode.F }),
		}, {
			bindingName = "NPC block",
			rebindable = true,
		})
		const action = PlayerInputServiceUtils.createAction("Combat", {
			Id = 100,
			Name = "NPC_BLOCK",
			InputKeyMapList = inputKeyMapList,
			AllowedContexts = { "Default", "Gameplay" },
			Network = {
				States = { "Begin", "End" },
				Capacity = 20,
				RefillRate = 20,
			},
		})
		registry:RegisterProvider({
			GetActions = function()
				return { action }
			end,
			GetContexts = function()
				return {
					table.freeze({ Name = "Gameplay", Priority = 10 }),
					table.freeze({ Name = "Menu", Priority = 20 }),
				}
			end,
		})
		registry:Start()

		const npc = Instance.new("Model")
		const humanoid = Instance.new("Humanoid")
		humanoid.Parent = npc
		const states = {}
		const policyContexts = {}
		const model = PlayerInputActorModel.new(npc, registry, {} :: any, 100, 100, function(_action, state)
			table.insert(states, state)
		end, function(_revision, _addedActionIds, _removedActionIds, contextName)
			table.insert(policyContexts, contextName)
		end)

		expect(model:TryInput(action, "Begin")).toEqual(PlayerInputResults.Accepted)
		expect(model:TryInput(action, "Begin")).toEqual(PlayerInputResults.AlreadyHeld)
		expect(model:TryInput(action, "End")).toEqual(PlayerInputResults.Accepted)
		expect(model:TryInput(action, "End")).toEqual(PlayerInputResults.NotHeld)
		expect(states).toEqual({ "Begin", "End" })

		const removeMenu = model:PushContext("Menu")
		expect(model:TryInput(action, "Begin")).toEqual(PlayerInputResults.ContextDenied)
		removeMenu()

		const removeRestriction = model:PushRestriction({
			Priority = 100,
			Actions = { action },
			Allowed = false,
		})
		expect(model:TryInput(action, "Begin")).toEqual(PlayerInputResults.RestrictionDenied)
		removeRestriction()

		expect(policyContexts).toEqual({})

		model:Destroy()
		registry:Destroy()
		inputKeyMapList:Destroy()
		npc:Destroy()
	end)

	it("reports server enablement, state, condition, and rate-limit failures", function()
		const registry = setmetatable({}, { __index = PlayerInputActionRegistryServiceShared }) :: any
		registry:Init({})

		const localInputKeyMapList = InputKeyMapList.fromInputKeys({ Enum.KeyCode.Q })
		const localAction = PlayerInputServiceUtils.createAction("Combat", {
			Id = 101,
			Name = "LOCAL",
			InputKeyMapList = localInputKeyMapList,
		})
		const inputKeyMapList = InputKeyMapList.fromInputKeys({ Enum.KeyCode.E })
		const action = PlayerInputServiceUtils.createAction("Combat", {
			Id = 102,
			Name = "ATTACK",
			InputKeyMapList = inputKeyMapList,
			AdorneeConditionContext = function(conditionContainer)
				AdorneeConditionUtils.createRequiredAttribute("CanAttack", true).Parent = conditionContainer
			end,
			Network = {
				States = { "Begin" },
				Capacity = 1,
				RefillRate = 0.0001,
			},
		})
		registry:RegisterProvider({
			GetActions = function()
				return { localAction, action }
			end,
			GetContexts = function()
				return {}
			end,
		})
		registry:Start()

		const npc = Instance.new("Model")
		const humanoid = Instance.new("Humanoid")
		humanoid.Parent = npc
		npc:SetAttribute("CanAttack", false)
		const model = PlayerInputActorModel.new(npc, registry, {} :: any, 100, 100, function() end, function() end)

		expect(model:TryInput(table.clone(action) :: any, "Begin")).toEqual(PlayerInputResults.ActionNotRegistered)
		expect(model:TryInput(localAction, "Begin")).toEqual(PlayerInputResults.ActionNotServerEnabled)
		expect(model:TryInput(action, "End")).toEqual(PlayerInputResults.StateNotAllowed)
		expect(model:TryInput(action, "Begin")).toEqual(PlayerInputResults.ConditionFailed)

		npc:SetAttribute("CanAttack", true)
		expect(model:TryInput(action, "Begin")).toEqual(PlayerInputResults.Accepted)
		expect(model:TryInput(action, "Begin")).toEqual(PlayerInputResults.RateLimited)

		model:Destroy()
		registry:Destroy()(action.AdorneeConditionContext :: BindableFunction):Destroy()
		localInputKeyMapList:Destroy()
		inputKeyMapList:Destroy()
		npc:Destroy()
	end)
end)
