--!strict
--[=[
	Unit tests for authoritative input actor validation.

	@class PlayerInputActorUtils.spec
]=]
const Jest = require("@game/ReplicatedStorage/Packages/Jest")
const PlayerInputActorUtils = require("./PlayerInputActorUtils")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("PlayerInputActorUtils", function()
	it("accepts Players and Humanoid Models", function()
		const player = Instance.new("Player")
		const npc = Instance.new("Model")
		const humanoid = Instance.new("Humanoid")
		humanoid.Parent = npc
		const modelWithoutHumanoid = Instance.new("Model")
		const folder = Instance.new("Folder")

		expect(PlayerInputActorUtils.isInputActor(player)).toEqual(true)
		expect(PlayerInputActorUtils.isInputActor(npc)).toEqual(true)
		expect(PlayerInputActorUtils.isInputActor(modelWithoutHumanoid)).toEqual(false)
		expect(PlayerInputActorUtils.isInputActor(folder)).toEqual(false)

		player:Destroy()
		npc:Destroy()
		modelWithoutHumanoid:Destroy()
		folder:Destroy()
	end)
end)
