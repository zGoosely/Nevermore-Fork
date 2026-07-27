--!strict
--[=[
	Unit tests for optional PlayerInput cooldown binding validation.

	@class PlayerInputCooldownServiceUtils.spec
]=]

const require = require("../../Loader").load()

const ActionExecutionStatuses = require("ActionExecutionStatuses")
const CooldownTypes = require("CooldownTypes")
const Jest = require("Jest")
const PlayerInputCooldownServiceUtils = require("PlayerInputCooldownServiceUtils")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("PlayerInputCooldownServiceUtils", function()
	it("validates realm-specific binding configurations", function()
		const player = Instance.new("Player")
		const npc = Instance.new("Model")
		const humanoid = Instance.new("Humanoid")
		humanoid.Parent = npc
		const owner = Instance.new("Folder")
		const action = { Id = 10 }
		const cooldownAction = {
			Id = 11,
			CooldownKey = "Combat.Dash",
			CooldownType = CooldownTypes.Default,
			CooldownValue = {
				Duration = 2,
			},
			CooldownOnCancel = false,
		}

		expect(PlayerInputCooldownServiceUtils.isServerBindingConfig({
			Player = player,
			Owner = owner,
			Key = "Dash",
			Actions = { action },
		})).toEqual(true)
		const actorConfig = {
			Actor = npc,
			Owner = owner,
			Key = "Dash",
			Actions = { action },
		}
		expect(PlayerInputCooldownServiceUtils.isServerBindingConfig(actorConfig)).toEqual(true)
		expect(PlayerInputCooldownServiceUtils.getServerBindingActor(actorConfig :: any)).toEqual(npc)
		expect(PlayerInputCooldownServiceUtils.isServerBindingConfig({
			Actor = npc,
			Player = player,
			Owner = owner,
			Key = "Dash",
			Actions = { action },
		})).toEqual(false)
		expect(PlayerInputCooldownServiceUtils.isClientBindingConfig({
			Owner = owner,
			Key = "Dash",
			Actions = { action },
		})).toEqual(true)
		expect(PlayerInputCooldownServiceUtils.isClientBindingConfig({
			Owner = owner,
			Key = "",
			Actions = { action },
		})).toEqual(false)
		expect(PlayerInputCooldownServiceUtils.isClientBindingConfig({
			Owner = owner,
			Key = "Dash",
			Actions = {},
		})).toEqual(false)
		expect(PlayerInputCooldownServiceUtils.isActionCooldownConfigured(cooldownAction)).toEqual(true)
		const key, cooldownType, cooldownValue =
			PlayerInputCooldownServiceUtils.getActionCooldownDefinition(cooldownAction :: any)
		expect(key).toEqual("Combat.Dash")
		expect(cooldownType).toEqual(CooldownTypes.Default)
		expect(cooldownValue).toEqual({
			Duration = 2,
		})
		expect(PlayerInputCooldownServiceUtils.isServerActionBindingConfig({
			Actor = npc,
			Owner = owner,
			Action = cooldownAction,
		})).toEqual(true)
		expect(PlayerInputCooldownServiceUtils.isClientActionBindingConfig({
			Owner = owner,
			Action = cooldownAction,
		})).toEqual(true)
		expect(
			PlayerInputCooldownServiceUtils.shouldStartActionCooldown(
				cooldownAction :: any,
				ActionExecutionStatuses.SUCCEEDED
			)
		).toEqual(true)
		expect(
			PlayerInputCooldownServiceUtils.shouldStartActionCooldown(
				cooldownAction :: any,
				ActionExecutionStatuses.CANCELLED
			)
		).toEqual(false)
		cooldownAction.CooldownOnCancel = true
		expect(
			PlayerInputCooldownServiceUtils.shouldStartActionCooldown(
				cooldownAction :: any,
				ActionExecutionStatuses.CANCELLED
			)
		).toEqual(true)
		expect(
			PlayerInputCooldownServiceUtils.shouldStartActionCooldown(
				cooldownAction :: any,
				ActionExecutionStatuses.FAILED
			)
		).toEqual(false)
		expect(
			PlayerInputCooldownServiceUtils.shouldStartActionCooldown(
				cooldownAction :: any,
				ActionExecutionStatuses.TIMED_OUT
			)
		).toEqual(false)
		cooldownAction.CooldownValue.Duration = -1
		expect(PlayerInputCooldownServiceUtils.isActionCooldownConfigured(cooldownAction)).toEqual(false)

		player:Destroy()
		npc:Destroy()
		owner:Destroy()
	end)
end)
