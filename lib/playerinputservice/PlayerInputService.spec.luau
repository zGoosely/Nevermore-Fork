--!strict
--[=[
	Unit tests for registered NPC actor lifetimes and generalized observations.

	@class PlayerInputService.spec
]=]

const require = require("../Loader").load()

const Brio = require("Brio")
const InputKeyMapList = require("InputKeyMapList")
const Jest = require("Jest")
const Observable = require("Observable")
const PlayerInputActionRegistryServiceShared = require("PlayerInputActionRegistryServiceShared")
const PlayerInputModeService = require("PlayerInputModeService")
const PlayerInputResults = require("PlayerInputResults")
const PlayerInputService = require("PlayerInputService")
const PlayerInputServiceTypes = require("PlayerInputServiceTypes")
const PlayerInputServiceUtils = require("PlayerInputServiceUtils")

type InputActor = PlayerInputServiceTypes.InputActor

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("PlayerInputService actors", function()
	it("reference-counts NPC registration and emits accepted actor inputs", function()
		const registry = setmetatable({}, { __index = PlayerInputActionRegistryServiceShared }) :: any
		registry:Init({})
		const inputKeyMapList = InputKeyMapList.fromInputKeys({ Enum.KeyCode.E })
		const action = PlayerInputServiceUtils.createAction("Combat", {
			Id = 110,
			Name = "NPC_ATTACK",
			InputKeyMapList = inputKeyMapList,
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
				return {}
			end,
		})
		registry:Start()

		const inputModeService = {
			ObservePlayerInputType = function()
				return Observable.new(function() end)
			end,
		}
		const serviceBag = {
			GetService = function(_self, serviceType)
				if serviceType == PlayerInputActionRegistryServiceShared then
					return registry
				elseif serviceType == PlayerInputModeService then
					return inputModeService
				end
				error("Unexpected service")
			end,
		}
		const service = setmetatable({}, { __index = PlayerInputService }) :: any
		service:Init(serviceBag)

		const npc = Instance.new("Model")
		const humanoid = Instance.new("Humanoid")
		humanoid.Parent = npc
		const observed = {}
		const subscription = service:ObserveInput(action):Subscribe(function(actor, state)
			table.insert(observed, { actor, state })
		end)
		local observedActorCount = 0
		local observedActorBrio: Brio.Brio<InputActor>? = nil
		const actorSubscription = service:ObserveActorsBrio():Subscribe(function(brio)
			observedActorCount += 1
			observedActorBrio = brio
		end)

		expect(service:TriggerActorInput(npc, action, "Begin")).toEqual(PlayerInputResults.ActorNotRegistered)

		const unregisterFirst = service:RegisterActor(npc)
		const unregisterSecond = service:RegisterActor(npc)
		expect(observedActorCount).toEqual(1)
		const firstActorBrio = observedActorBrio
		assert(firstActorBrio, "Expected the registered actor brio")
		expect(firstActorBrio:IsDead()).toEqual(false)
		expect(service:TriggerActorInput(npc, action, "Begin")).toEqual(PlayerInputResults.Accepted)
		expect(service:IsActorInputHeld(npc, action)).toEqual(true)

		unregisterFirst()
		expect(service:TriggerActorInput(npc, action, "End")).toEqual(PlayerInputResults.Accepted)

		expect(service:TriggerActorInput(npc, action, "Begin")).toEqual(PlayerInputResults.Accepted)
		unregisterSecond()
		expect(observed).toEqual({
			{ npc, "Begin" },
			{ npc, "End" },
			{ npc, "Begin" },
			{ npc, "Cancel" },
		})
		expect(firstActorBrio:IsDead()).toEqual(true)
		expect(service:TriggerActorInput(npc, action, "Begin")).toEqual(PlayerInputResults.ActorNotRegistered)

		const unregisterHumanoidLifetime = service:RegisterActor(npc)
		expect(observedActorCount).toEqual(2)
		const secondActorBrio = observedActorBrio
		assert(secondActorBrio, "Expected the re-registered actor brio")
		expect(secondActorBrio:IsDead()).toEqual(false)
		humanoid:Destroy()
		expect(secondActorBrio:IsDead()).toEqual(true)
		expect(service._actorRecords[npc]).toEqual(nil)
		unregisterHumanoidLifetime()

		actorSubscription:Destroy()
		subscription:Destroy()
		service:Destroy()
		registry:Destroy()
		inputKeyMapList:Destroy()
		npc:Destroy()
	end)
end)
