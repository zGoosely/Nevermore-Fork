--!strict
--[=[
	Unit tests for move-owned character condition evaluation.

	@class PlayerInputActionConditionModel.spec
]=]

const require = require("../../Loader").load()

const AdorneeConditionUtils = require("AdorneeConditionUtils")
const InputKeyMap = require("InputKeyMap")
const InputKeyMapList = require("InputKeyMapList")
const InputModeTypes = require("InputModeTypes")
const Jest = require("Jest")
const PlayerInputActionConditionModel = require("PlayerInputActionConditionModel")
const PlayerInputServiceUtils = require("PlayerInputServiceUtils")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("PlayerInputActionConditionModel", function()
	it("fails closed without a character and follows character attributes", function()
		const inputKeyMapList = InputKeyMapList.new("PUNCH", {
			InputKeyMap.new(InputModeTypes.KeyboardAndMouse, { Enum.UserInputType.MouseButton1 }),
		}, {
			bindingName = "Punch",
			rebindable = true,
		})
		const action = PlayerInputServiceUtils.createAction("Combat", {
			Id = 1,
			Name = "PUNCH",
			InputKeyMapList = inputKeyMapList,
			AdorneeConditionContext = function(conditionContainer)
				AdorneeConditionUtils.createRequiredAttribute("CanAttack", true).Parent = conditionContainer
				AdorneeConditionUtils.createRequiredAttribute("IsStunned", false).Parent = conditionContainer
			end,
		})
		const player = Instance.new("Player")
		const model = PlayerInputActionConditionModel.new(player, action)

		expect(model:AreConditionsMet()).toEqual(false)

		const character = Instance.new("Model")
		character:SetAttribute("CanAttack", true)
		character:SetAttribute("IsStunned", false)
		player.Character = character
		expect(model:AreConditionsMet()).toEqual(true)

		character:SetAttribute("IsStunned", true)
		expect(model:AreConditionsMet()).toEqual(false)
		character:SetAttribute("IsStunned", false)
		expect(model:AreConditionsMet()).toEqual(true)

		player.Character = nil
		expect(model:AreConditionsMet()).toEqual(false)

		model:Destroy()
		player:Destroy()
		character:Destroy()(action.AdorneeConditionContext :: BindableFunction):Destroy()
		inputKeyMapList:Destroy()
	end)

	it("evaluates a Humanoid NPC Model directly", function()
		const inputKeyMapList = InputKeyMapList.new("NPC_PUNCH", {
			InputKeyMap.new(InputModeTypes.KeyboardAndMouse, { Enum.UserInputType.MouseButton1 }),
		}, {
			bindingName = "NPC punch",
			rebindable = true,
		})
		const action = PlayerInputServiceUtils.createAction("Combat", {
			Id = 2,
			Name = "NPC_PUNCH",
			InputKeyMapList = inputKeyMapList,
			AdorneeConditionContext = function(conditionContainer)
				AdorneeConditionUtils.createRequiredAttribute("CanAttack", true).Parent = conditionContainer
			end,
		})
		const npc = Instance.new("Model")
		const humanoid = Instance.new("Humanoid")
		humanoid.Parent = npc
		npc:SetAttribute("CanAttack", false)
		const model = PlayerInputActionConditionModel.new(npc, action)

		expect(model:AreConditionsMet()).toEqual(false)
		npc:SetAttribute("CanAttack", true)
		expect(model:AreConditionsMet()).toEqual(true)

		model:Destroy()
		npc:Destroy()(action.AdorneeConditionContext :: BindableFunction):Destroy()
		inputKeyMapList:Destroy()
	end)
end)
