--!strict
--[=[
	Unit tests for execution configuration and runtime tags.

	@class ActionExecutionUtils.spec
]=]
const ActionExecutionUtils = require("./ActionExecutionUtils")
const Jest = require("@game/ReplicatedStorage/Packages/Jest")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("ActionExecutionUtils", function()
	it("validates optional locks and unique runtime tags", function()
		const actor = Instance.new("Folder")

		expect(ActionExecutionUtils.isExecutionConfig({
			Actor = actor,
			Tags = { "Combat", "Barrage" },
			Timeout = 5,
			Lock = {
				Key = "SharedPrimary",
			},
		})).toEqual(true)
		expect(ActionExecutionUtils.isExecutionConfig({
			Actor = actor,
			Tags = { "Combat", "Combat" },
			Timeout = 5,
		})).toEqual(false)
		expect(ActionExecutionUtils.isExecutionConfig({
			Actor = actor,
			Timeout = 0,
		})).toEqual(false)

		actor:Destroy()
	end)
end)
