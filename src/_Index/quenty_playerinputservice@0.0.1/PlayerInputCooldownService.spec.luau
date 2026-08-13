--!strict
--[=[
	Unit tests for automatic cooldown binding and action-execution completion
	policies.

	@class PlayerInputCooldownService.spec
]=]
const ActionExecutionService = require("@game/ReplicatedStorage/Packages/ActionExecutionService")
const Brio = require("@game/ReplicatedStorage/Packages/Brio")
const CooldownService = require("@game/ReplicatedStorage/Packages/CooldownService")
const CooldownTypes = require("@game/ReplicatedStorage/Packages/CooldownTypes")
const InputKeyMapList = require("@game/ReplicatedStorage/Packages/InputKeyMapList")
const Jest = require("@game/ReplicatedStorage/Packages/Jest")
const LockService = require("@game/ReplicatedStorage/Packages/LockService")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const PlayerInputActionRegistryServiceShared = require("./Shared/PlayerInputActionRegistryServiceShared")
const PlayerInputCooldownService = require("./PlayerInputCooldownService")
const PlayerInputService = require("./PlayerInputService")
const PlayerInputServiceTypes = require("./Shared/PlayerInputServiceTypes")
const PlayerInputServiceUtils = require("./Shared/PlayerInputServiceUtils")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")

type Action = PlayerInputServiceTypes.Action

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

local function createAction(
	id: number,
	name: string,
	cooldownOnCancel: boolean
): (Action, InputKeyMapList.InputKeyMapList)
	const inputKeyMapList = InputKeyMapList.fromInputKeys({ Enum.KeyCode.E })
	return PlayerInputServiceUtils.createAction("Combat", {
		Id = id,
		Name = name,
		InputKeyMapList = inputKeyMapList,
		CooldownType = CooldownTypes.Default,
		CooldownValue = {
			Duration = 1,
		},
		CooldownOnCancel = cooldownOnCancel,
	}),
		inputKeyMapList
end

describe("PlayerInputCooldownService", function()
	it("automatically binds actions and starts cooldowns from execution results", function()
		const registry = setmetatable({}, { __index = PlayerInputActionRegistryServiceShared }) :: any
		registry:Init({})

		const succeededAction, succeededKeyMapList = createAction(120, "SUCCEED", false)
		const cancelledAction, cancelledKeyMapList = createAction(121, "CANCEL", false)
		const cancelledCooldownAction, cancelledCooldownKeyMapList = createAction(122, "CANCEL_WITH_COOLDOWN", true)
		const failedAction, failedKeyMapList = createAction(123, "FAIL", false)
		registry:RegisterProvider({
			GetActions = function()
				return {
					succeededAction,
					cancelledAction,
					cancelledCooldownAction,
					failedAction,
				}
			end,
			GetContexts = function()
				return {}
			end,
		})
		registry:Start()

		const lockService = setmetatable({}, { __index = LockService }) :: any
		lockService:Init({})
		const actionExecutionService = setmetatable({}, { __index = ActionExecutionService }) :: any
		actionExecutionService:Init({
			GetService = function()
				return lockService
			end,
		})

		const actor = Instance.new("Model")
		const humanoid = Instance.new("Humanoid")
		humanoid.Parent = actor
		local isOnCooldown = false
		local observedCooldownCount = 0
		const startedActions = {}
		const cooldownService = {
			ObserveIsOnCooldown = function(_self, _owner, _key)
				observedCooldownCount += 1
				return Observable.new(function(sub)
					sub:Fire(isOnCooldown)
				end)
			end,
			IsOnCooldown = function(_self, _owner, _key)
				return isOnCooldown
			end,
			StartTypedCooldown = function(_self, _owner, key, cooldownType, cooldownValue)
				isOnCooldown = true
				table.insert(startedActions, {
					Key = key,
					Type = cooldownType,
					Value = cooldownValue,
				})
				return nil
			end,
		}
		const actorBrio = Brio.new(actor)
		const playerInputService = {
			ObserveActorsBrio = function()
				return Observable.new(function(sub)
					sub:Fire(actorBrio)
					return actorBrio
				end)
			end,
			PushActorRestriction = function()
				return function() end
			end,
		}
		const serviceBag = {
			GetService = function(_self, serviceType)
				if serviceType == ActionExecutionService then
					return actionExecutionService
				elseif serviceType == PlayerInputActionRegistryServiceShared then
					return registry
				elseif serviceType == CooldownService then
					return cooldownService
				elseif serviceType == PlayerInputService then
					return playerInputService
				end
				error("Unexpected service")
			end,
		}
		const service = setmetatable({}, { __index = PlayerInputCooldownService }) :: any
		service:Init(serviceBag)
		service:Start()

		expect(observedCooldownCount).toEqual(4)

		const executionConfig = {
			Actor = actor,
			Timeout = 5,
			Lock = {
				Key = "CombatAction",
			},
		}
		local succeededCallbackCount = 0
		const succeededExecution = service:TryStartActionExecution(succeededAction, executionConfig, function()
			succeededCallbackCount += 1
			return Promise.resolved()
		end)
		expect(succeededExecution).never.toEqual(nil)
		task.wait()
		expect(succeededCallbackCount).toEqual(1)
		expect(#startedActions).toEqual(1)
		expect(startedActions[1].Key).toEqual("Combat.SUCCEED")

		const deniedExecution = service:TryStartActionExecution(succeededAction, executionConfig, function()
			succeededCallbackCount += 1
			return Promise.resolved()
		end)
		expect(deniedExecution).toEqual(nil)
		expect(succeededCallbackCount).toEqual(1)

		isOnCooldown = false
		const cancelledExecution = service:TryStartActionExecution(
			cancelledAction,
			executionConfig,
			function(cancelToken)
				return cancelToken.PromiseCancelled:Then(function()
					return Promise.rejected(cancelToken:GetReason())
				end)
			end
		)
		expect(cancelledExecution).never.toEqual(nil)
		assert(cancelledExecution, "Expected the cancelled execution to start")
		task.wait()
		cancelledExecution:Cancel("Stunned")
		task.wait()
		expect(#startedActions).toEqual(1)

		isOnCooldown = false
		const cancelledCooldownExecution = service:TryStartActionExecution(
			cancelledCooldownAction,
			executionConfig,
			function(cancelToken)
				return cancelToken.PromiseCancelled:Then(function()
					return Promise.rejected(cancelToken:GetReason())
				end)
			end
		)
		expect(cancelledCooldownExecution).never.toEqual(nil)
		assert(cancelledCooldownExecution, "Expected the cancel-cooldown execution to start")
		task.wait()
		cancelledCooldownExecution:Cancel("InputReleased")
		task.wait()
		expect(#startedActions).toEqual(2)
		expect(startedActions[2].Key).toEqual("Combat.CANCEL_WITH_COOLDOWN")

		isOnCooldown = false
		const failedExecution = service:TryStartActionExecution(failedAction, executionConfig, function()
			return Promise.rejected("Failed")
		end)
		expect(failedExecution).never.toEqual(nil)
		task.wait()
		expect(#startedActions).toEqual(2)

		service:Destroy()
		actionExecutionService:Destroy()
		lockService:Destroy()
		registry:Destroy()
		succeededKeyMapList:Destroy()
		cancelledKeyMapList:Destroy()
		cancelledCooldownKeyMapList:Destroy()
		failedKeyMapList:Destroy()
		actor:Destroy()
	end)
end)
